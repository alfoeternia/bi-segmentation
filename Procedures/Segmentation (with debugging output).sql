create or replace PROCEDURE SEGMENTATION_DEBUG
AS
  debug_file UTL_FILE.FILE_TYPE;
  
 	routeID VARCHAR2(50); -- Temporary

	section_begin_point NUMBER(7,3);
	section_end_point NUMBER(7,3);

	LRS_ROUTE ALFO_TEST.shape%TYPE;

	segment HPMS_SEGMENTED%ROWTYPE;
	remaining_section ALFO_TEST.shape%TYPE;

	first_segment HPMS_SEGMENTED.geometry%TYPE;
	second_segment HPMS_SEGMENTED.geometry%TYPE;

	counter INTEGER := 0;
	lastID NUMBER := 0;
BEGIN

debug_file := UTL_FILE.FOPEN ('TEST_ALFO_DIR', 'HPMS_full.txt', 'W');

FOR cursor2 IN (select ROUTE_ID from hpms_section group by route_id order by count(route_id) desc) LOOP
  routeID := cursor2.ROUTE_ID;
  --routeID := '5EL';
	-- Loop over each segment of a same road
	FOR cursor IN (SELECT * FROM HPMS_SECTION HPMS WHERE HPMS.ROUTE_ID = routeID AND HPMS.SHAPE.SDO_GTYPE = 2002) LOOP
		
		section_begin_point := cursor.BEG_POINT;
		section_end_point := cursor.END_POINT;

		-- SDO_GEOMETRY (Shape) is converted to LRS Geometry
		LRS_ROUTE := SDO_LRS.CONVERT_TO_LRS_GEOM(cursor.SHAPE, cursor.BEG_POINT, cursor.END_POINT);

		UTL_FILE.PUT_LINE (debug_file, '-----------------------------------------');
		UTL_FILE.PUT_LINE (debug_file, 'Processing segment #' || (COUNTER+1) || ' (ID: ' || cursor.OBJECTID || ')...');
		UTL_FILE.PUT_LINE (debug_file, 'Start/End Point: ' || cursor.BEG_POINT || ' -> ' || cursor.END_POINT);
		UTL_FILE.PUT_LINE (debug_file, 'Length: ' || (SDO_LRS.GEOM_SEGMENT_END_MEASURE(LRS_ROUTE) - SDO_LRS.GEOM_SEGMENT_START_MEASURE(LRS_ROUTE)));
    UTL_FILE.FFLUSH(debug_file);

		-- While the segment has not been entirely processed
		WHILE section_begin_point < section_end_point LOOP

			UTL_FILE.PUT_LINE (debug_file, 'Iteration with: [BEGIN_POINT: ' || section_begin_point || '] [END_POINT: ' || section_end_point || ']');
      UTL_FILE.FFLUSH(debug_file);
			-- Split the section to what is left to be inserted
			remaining_section := SDO_LRS.CLIP_GEOM_SEGMENT(LRS_ROUTE, section_begin_point, section_end_point);

			-- Fetch the first overlapping segment of the segmented table
			BEGIN
				SELECT * INTO segment FROM 
					(SELECT * FROM HPMS_SEGMENTED
					WHERE ROUTE_ID = routeID
						AND (BEG_POINT <= section_end_point AND END_POINT > section_begin_point)
					ORDER BY BEG_POINT)
				WHERE ROWNUM = 1;



				EXCEPTION
			    WHEN NO_DATA_FOUND THEN
			        segment.OBJECTID := NULL;
		    END;

			-- Not segment is found, then simply insert the full section to the table
			IF segment.OBJECTID IS NULL THEN

				UTL_FILE.PUT_LINE (debug_file, 'Result: No overlapping segment! Just insert the segment into the table!');
        UTL_FILE.FFLUSH(debug_file);

				INSERT INTO HPMS_SEGMENTED (OBJECTID, YEAR_RECOR, STATE_CODE, ROUTE_ID, BEG_POINT, END_POINT, SECTION_LE, COMMENTS, GEOMETRY)
		        VALUES (null, cursor.YEAR_RECOR, cursor.STATE_CODE, cursor.ROUTE_ID, section_begin_point, section_end_point, cursor.SECTION_LE, cursor.COMMENTS, SDO_LRS.CONVERT_TO_STD_GEOM(remaining_section));
		        
		        SELECT HPMS_segmented_seq.CURRVAL INTO lastID FROM dual;
		        UPDATE_SEGMENTED_FIELD(lastID, cursor.DATA_ITEM, cursor.VALUE_NUME, cursor.VALUE_TEXT, cursor.VALUE_DATE);
				
		        UTL_FILE.PUT_LINE (debug_file, 'Inserted [ID: ' || lastID || '] [BEGIN_POINT: ' || section_begin_point || '] [END_POINT: ' || section_end_point || ']');
            UTL_FILE.FFLUSH(debug_file);
		        
				-- Set the begin point equal to the last point, so the loop will end at next round
				section_begin_point := section_end_point;

			-- The first segment found is further, we should only insert the first part of the section up to the beginning of the segment
			ELSIF segment.BEG_POINT > section_begin_point THEN

				UTL_FILE.PUT_LINE (debug_file, 'Result: The first segment found is further [BEGIN_POINT: ' || segment.BEG_POINT || ']!');
        UTL_FILE.FFLUSH(debug_file);

				remaining_section := SDO_LRS.CLIP_GEOM_SEGMENT(LRS_ROUTE, section_begin_point, segment.BEG_POINT);
				INSERT INTO HPMS_SEGMENTED (OBJECTID, YEAR_RECOR, STATE_CODE, ROUTE_ID, BEG_POINT, END_POINT, SECTION_LE, COMMENTS, GEOMETRY)
		        VALUES (null, cursor.YEAR_RECOR, cursor.STATE_CODE, cursor.ROUTE_ID, section_begin_point, segment.BEG_POINT, cursor.SECTION_LE, cursor.COMMENTS, SDO_LRS.CONVERT_TO_STD_GEOM(remaining_section));
		        
		        SELECT segmented_seq.CURRVAL INTO lastID FROM dual;
		        UPDATE_SEGMENTED_FIELD(lastID, cursor.DATA_ITEM, cursor.VALUE_NUME, cursor.VALUE_TEXT, cursor.VALUE_DATE);

		        UTL_FILE.PUT_LINE (debug_file, 'Inserted [ID: ' || lastID || '] [BEGIN_POINT: ' || section_begin_point || '] [END_POINT: ' || segment.BEG_POINT || ']');
            UTL_FILE.FFLUSH(debug_file);

				section_begin_point := segment.BEG_POINT;

			-- Trying to insert the section over a segment.
			ELSIF segment.BEG_POINT <= section_begin_point THEN
				UTL_FILE.PUT_LINE (debug_file, 'Result: Collision with an existing segment [OBJECTID: ' || segment.OBJECTID || '] [BEGIN_POINT: ' || segment.BEG_POINT || ']  [END_POINT: ' || segment.END_POINT || ']!');
        UTL_FILE.FFLUSH(debug_file);

				-- If both the section and the segment shares the same begin point
				IF segment.BEG_POINT = section_begin_point THEN
					UTL_FILE.PUT_LINE (debug_file, 'Result: Both the section and the section shares the begin point!');
          UTL_FILE.FFLUSH(debug_file);

					-- Segment and section are entirely overlapping
					IF section_end_point >= segment.END_POINT THEN
						UTL_FILE.PUT_LINE (debug_file, 'Result: Segment and section are entirely overlapping!');
            UTL_FILE.FFLUSH(debug_file);
						UPDATE_SEGMENTED_FIELD(segment.OBJECTID, cursor.DATA_ITEM, cursor.VALUE_NUME, cursor.VALUE_TEXT, cursor.VALUE_DATE);
						section_begin_point := segment.END_POINT;

					--  Segment and section are NOT entirely overlapping
					ELSIF section_end_point < segment.END_POINT THEN
						UTL_FILE.PUT_LINE (debug_file, 'Result: Segment and section are NOT entirely overlapping!');
            UTL_FILE.FFLUSH(debug_file);
						
						first_segment := SDO_LRS.CLIP_GEOM_SEGMENT(SDO_LRS.CONVERT_TO_LRS_GEOM(segment.GEOMETRY, segment.BEG_POINT, segment.END_POINT), section_begin_point, section_end_point);
						second_segment := SDO_LRS.CLIP_GEOM_SEGMENT(SDO_LRS.CONVERT_TO_LRS_GEOM(segment.GEOMETRY, segment.BEG_POINT, segment.END_POINT), section_end_point, segment.END_POINT);

						UPDATE HPMS_SEGMENTED SET
							OBJECTID = segmented_seq.NEXTVAL,
							END_POINT = section_end_point,
							GEOMETRY = SDO_LRS.CONVERT_TO_STD_GEOM(first_segment) WHERE OBJECTID = segment.OBJECTID;

						SELECT segmented_seq.CURRVAL INTO lastID FROM dual;
						UPDATE_SEGMENTED_FIELD(lastID, cursor.DATA_ITEM, cursor.VALUE_NUME, cursor.VALUE_TEXT, cursor.VALUE_DATE);
			      		
			     	 	UTL_FILE.PUT_LINE (debug_file, 'Updated [ID: ' || segment.OBJECTID || '] to [ID: ' || lastID || '] [BEGIN_POINT: ' || section_begin_point || '] [END_POINT: ' || section_end_point || ']');
              UTL_FILE.FFLUSH(debug_file);
			        
						segment.OBJECTID := null;
						segment.BEG_POINT := section_end_point;
						--segment.SHAPE :=  SDO_LRS.CONVERT_TO_LRS_GEOM(second_segment);
						INSERT INTO HPMS_SEGMENTED VALUES segment;

						SELECT segmented_seq.CURRVAL INTO lastID FROM dual;
						UPDATE HPMS_SEGMENTED SET GEOMETRY = SDO_LRS.CONVERT_TO_STD_GEOM(second_segment) WHERE OBJECTID = lastID;
						UTL_FILE.PUT_LINE (debug_file, 'Inserted [ID: ' || lastID || '] [BEGIN_POINT: ' || section_end_point || '] [END_POINT: ' || segment.END_POINT || ']');
            UTL_FILE.FFLUSH(debug_file);
						
						--TODO: UPDATE left side OF the segment

						section_begin_point := section_end_point;
					END IF;

				-- Section is a subset of the segment. Need to split up to section_begin_point and the next iteration will do the job.
				ELSE
					UTL_FILE.PUT_LINE (debug_file, 'Result: Section is a subset of the segment. Need to split up to section_begin_point and the next iteration will do the job.');
          UTL_FILE.FFLUSH(debug_file);

					first_segment := SDO_LRS.CLIP_GEOM_SEGMENT(SDO_LRS.CONVERT_TO_LRS_GEOM(segment.GEOMETRY, segment.BEG_POINT, segment.END_POINT), segment.BEG_POINT, section_begin_point);
					second_segment := SDO_LRS.CLIP_GEOM_SEGMENT(SDO_LRS.CONVERT_TO_LRS_GEOM(segment.GEOMETRY, segment.BEG_POINT, segment.END_POINT), section_begin_point, segment.END_POINT);

					UPDATE HPMS_SEGMENTED SET 
						OBJECTID = segmented_seq.NEXTVAL,
						END_POINT = section_begin_point,
						GEOMETRY = SDO_LRS.CONVERT_TO_STD_GEOM(first_segment) WHERE OBJECTID = segment.OBJECTID;

					SELECT segmented_seq.CURRVAL INTO lastID FROM dual;
		     	 	UTL_FILE.PUT_LINE (debug_file, 'Updated [ID: ' || segment.OBJECTID || '] to [ID: ' || lastID || '] [BEGIN_POINT: ' || segment.BEG_POINT || '] [END_POINT: ' || section_begin_point || ']');
            UTL_FILE.FFLUSH(debug_file);
		        
					segment.OBJECTID := null;
					segment.BEG_POINT := section_begin_point;
					--segment.SHAPE :=  SDO_LRS.CONVERT_TO_LRS_GEOM(second_segment);
					INSERT INTO HPMS_SEGMENTED VALUES segment;

					SELECT segmented_seq.CURRVAL INTO lastID FROM dual;
					UPDATE HPMS_SEGMENTED SET GEOMETRY = SDO_LRS.CONVERT_TO_STD_GEOM(second_segment) WHERE OBJECTID = lastID;
		      		UTL_FILE.PUT_LINE (debug_file, 'Inserted [ID: ' || lastID || '] [BEGIN_POINT: ' || section_begin_point || '] [END_POINT: ' || segment.END_POINT || ']');
              UTL_FILE.FFLUSH(debug_file);
		        

					
				END IF;
			END IF;   
		END LOOP;
    COMMIT;
		--counter := counter + 1;
	    --IF counter > 10 THEN 
			--goto end_proc;
		--END IF;
	END LOOP;

	--<<end_proc>>
	--null;  -- this could be a commit or other lines of code
END LOOP;
END;