SET SERVEROUTPUT ON;
DECLARE
	-- Step 1
	FFS 	NUMBER;
	BFFS 	NUMBER;
	fLW		NUMBER;
	fLC 	NUMBER;
	fN 		NUMBER;
	fID		NUMBER;
	LOD		NUMBER;

	-- Step 2
  BaseCap NUMBER;
  
  -- Step 3
  PeakCap NUMBER;
  PHF     NUMBER;
  N       NUMBER;
  fHV     NUMBER;
  fP      NUMBER;
  Terrain NUMBER;
  V       NUMBER;
  VC_RATIO NUMBER;
  
  -- Debug/Stats
  VC_AVG NUMBER;
  VC_COUNT NUMBER;
  VC_HIGH NUMBER;
BEGIN
  
  VC_AVG := 0;
  VC_COUNT := 0;
  VC_HIGH := 0;
  
	-- Loop over each segment
	FOR cursor IN (SELECT * FROM HPMS_CAPACITY WHERE 
    --THROUGH_LANES/FACILITY_TYPE >= 2 AND
    URBAN_CODE IS NOT NULL AND
    --LANE_WIDTH IS NOT NULL AND
    THROUGH_LANES IS NOT NULL AND
    FACILITY_TYPE IS NOT NULL AND
    --SHOULDER_WIDTH_R IS NOT NULL AND 
    AADT IS NOT NULL AND
    --PEAK_LANES IS NOT NULL AND
    PCT_PEAK_SINGLE IS NOT NULL AND
    PCT_PEAK_COMBINATION IS NOT NULL AND
    AADT IS NOT NULL AND
    K_FACTOR IS NOT NULL AND
    DIR_FACTOR IS NOT NULL
    ) LOOP
		
		DBMS_OUTPUT.PUT_LINE('-----------------------------------------');
		DBMS_OUTPUT.PUT_LINE('Processing segment #' || cursor.OBJECTID || '...');

		-- Step 1: Calculate Free Flow Speed (FFS)
		-- FFS 		= 	BFFS - fLW - fLC - fN - fID	(1)

		-- BFFS
		IF cursor.URBAN_CODE = 99999 THEN
			BFFS := 75;
		ELSE
			BFFS := 70;
		END IF;
		--DBMS_OUTPUT.PUT_LINE('BFFS: '|| BFFS);

		-- fLW
		IF cursor.LANE_WIDTH <= 10 THEN
			fLW := 6.6;
		ELSIF cursor.LANE_WIDTH = 11 THEN
			fLW := 1.9;
		ELSE
      fLW := 0.0;
		END IF;
		--DBMS_OUTPUT.PUT_LINE('fLW: ' || fLW);

    -- fLC
		LOD := cursor.THROUGH_LANES / cursor.FACILITY_TYPE;
    IF LOD > 5 THEN LOD := 5; END IF;
		CASE LOD
		   WHEN 2 THEN fLC := 0.6;
		   WHEN 3 THEN fLC := 0.4;
		   WHEN 4 THEN fLC := 0.2;
		   ELSE fLC := 0.1;
		END CASE;
		fLC := fLC * (((-1 * cursor.SHOULDER_WIDTH_R) + 6));
    IF fLC IS NULL THEN fLC := 0; END IF;
		--DBMS_OUTPUT.PUT_LINE('fLC: ' || fLC);
    
    -- fN (for urban highways only)
    IF cursor.URBAN_CODE < 99999 THEN
      fN := (((-1 * LOD)+5)*1.5);
    ELSE
      fN := 1.0;
    END IF;
    --DBMS_OUTPUT.PUT_LINE('fN: ' || fN);
    
    -- fID (unused since 1998)
    fID := 1.0;
    
    -- FFS final calculation
    FFS := BFFS - fLW - fLC - fN - fID;
    DBMS_OUTPUT.PUT_LINE('** FFS: ' || FFS);
    
    
    
    
    -- Step 2: Calculate Base Capacity (BaseCap)
    IF FFS <= 70 THEN
      BaseCap := 1700 + 10*FFS;
    ELSE
      BaseCap := 2400;
    END IF;
    
    DBMS_OUTPUT.PUT_LINE('** AADT: ' || cursor.AADT);
    DBMS_OUTPUT.PUT_LINE('** BaseCap: ' || BaseCap);
    
    
    
    -- Step 3: Calculate Peak Capacity (PeakCap)
    PHF := 1.0; -- Value set to 1.0 for pre-calculation
    IF cursor.PEAK_LANES = 0 OR cursor.PEAK_LANES IS NULL THEN
      N := LOD;
    ELSE N := cursor.PEAK_LANES;
    END IF;
    --IF cursor.TERRAIN_TYPE IS NOT NULL THEN
    --  Terrain := cursor.TERRAIN_TYPE;
    --ELSE 
    --  Terrain := 0.0;
    --END IF;
    fHV := 1.0 / (1 + (cursor.PCT_PEAK_SINGLE + cursor.PCT_PEAK_COMBINATION) * (1.5 - 1)); -- TODO: replace 1.5
    IF cursor.URBAN_CODE = 99999 THEN
			fP := 0.975;
		ELSE
			fP := 1.0;
		END IF;
    
    PeakCap := BaseCap * PHF * N * fHV * fP;
    DBMS_OUTPUT.PUT_LINE('PHF: ' || PHF);
    DBMS_OUTPUT.PUT_LINE('N: ' || N);
    DBMS_OUTPUT.PUT_LINE('fHV: ' || fHV);
    DBMS_OUTPUT.PUT_LINE('fP: ' || fP);
    
    -- Calculate the final Peak Capacity
    IF cursor.K_FACTOR = 0 THEN cursor.K_FACTOR := 8; END IF;
    V := cursor.AADT * cursor.K_FACTOR/100 * cursor.DIR_FACTOR/100;
    VC_RATIO := V / PeakCap;
    
    IF cursor.URBAN_CODE = 99999 THEN -- If rural
			IF VC_RATIO < 0.7744 THEN
        PHF := 0.88;
      ELSIF VC_RATIO > 0.9025 THEN
        PHF := 0.95;
      ELSE
        PHF := SQRT(0.9025 * VC_RATIO)/0.95;
      END IF;
      
		ELSE -- If urban
			IF VC_RATIO < 0.8100 THEN
        PHF := 0.90;
      ELSIF VC_RATIO > 0.9025 THEN
        PHF := 0.95;
      ELSE
        PHF := SQRT(0.9025 * VC_RATIO)/0.95;
      END IF;
		END IF;
    
    
    PeakCap := BaseCap * PHF * N * fHV * fP;
    VC_RATIO := V / PeakCap;
    --DBMS_OUTPUT.PUT_LINE('PHF: ' || PHF);
    DBMS_OUTPUT.PUT_LINE('** PeakCap: ' || ROUND(PeakCap));
    DBMS_OUTPUT.PUT_LINE('** Congestion: ' || ROUND(cursor.AADT/PeakCap, 3));
    DBMS_OUTPUT.PUT_LINE('** AADT: ' || ROUND(cursor.AADT, 3));
    DBMS_OUTPUT.PUT_LINE('** K_FACTOR: ' || ROUND(cursor.K_FACTOR, 3));
    DBMS_OUTPUT.PUT_LINE('** D_FACTOR: ' || ROUND(cursor.DIR_FACTOR, 3));
    DBMS_OUTPUT.PUT_LINE('** V/C Ratio: ' || ROUND(VC_RATIO, 3));
    
    VC_AVG := (VC_AVG * VC_COUNT + VC_RATIO) / (VC_COUNT+1);
    VC_COUNT := VC_COUNT+1;
    IF VC_RATIO > VC_HIGH THEN VC_HIGH := VC_RATIO; END IF;
    
    
		EXIT WHEN VC_RATIO = 0;
    
    UPDATE HPMS_CAPACITY SET BASE_CAP = BaseCap, PEAK_CAP = ROUND(PeakCap), VC = ROUND(VC_RATIO, 3) WHERE OBJECTID = cursor.OBJECTID;
    
    COMMIT;

	END LOOP;
  
  
		DBMS_OUTPUT.PUT_LINE('-----------------------------------------');
    DBMS_OUTPUT.PUT_LINE('** V/C AVG: ' || ROUND(VC_AVG, 3));
    DBMS_OUTPUT.PUT_LINE('** V/C High: ' || ROUND(VC_HIGH, 3));
END;