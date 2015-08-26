create or replace PROCEDURE parallel_seg_chunk(
    p_test_name IN VARCHAR2,
    start_id    IN NUMBER,
    end_id      IN NUMBER
)
IS
  routeID VARCHAR2(50);

	section_begin_point NUMBER(7,3);
	section_end_point NUMBER(7,3);

	LRS_ROUTE ALFO_TEST.shape%TYPE;

	segment ALFO_SEGMENTED%ROWTYPE;
	remaining_section ALFO_TEST.shape%TYPE;

	first_segment ALFO_SEGMENTED.shape%TYPE;
	second_segment ALFO_SEGMENTED.shape%TYPE;

	counter INTEGER := 0;
	lastID NUMBER := 0;
BEGIN
    select route_id INTO routeID from hpms_section where objectid = start_id;
    
    -- Loop over each segment of a same road
	FOR cursor IN (SELECT * FROM hpms_section HPMS WHERE HPMS.ROUTE_ID = routeID AND DATA_ITEM IN('F_SYSTEM', 'THROUGH_LANES', 'SPEED_LIMIT', 'ACCESS_CONTROL', 'URBAN_CODE', 'SHOULDER_TYPE', 'SHOULDER_WIDTH_R', 'SHOULDER_WIDTH_L')) LOOP
		
		section_begin_point := cursor.BEG_POINT;
		section_end_point := cursor.END_POINT;

		-- SDO_GEOMETRY (Shape) is converted to LRS Geometry
		LRS_ROUTE := SDO_LRS.CONVERT_TO_LRS_GEOM(cursor.SHAPE, cursor.BEG_POINT, cursor.END_POINT);

		--DBMS_OUTPUT.PUT_LINE('-----------------------------------------');
		--DBMS_OUTPUT.PUT_LINE('Processing segment #' || (COUNTER+1) || ' (ID: ' || cursor.OBJECTID || ')...');
		--DBMS_OUTPUT.PUT_LINE('Start/End Point: ' || cursor.BEG_POINT || ' -> ' || cursor.END_POINT);
		--DBMS_OUTPUT.PUT_LINE('Length: ' || (SDO_LRS.GEOM_SEGMENT_END_MEASURE(LRS_ROUTE) - SDO_LRS.GEOM_SEGMENT_START_MEASURE(LRS_ROUTE)));

		-- While the segment has not been entirely processed
		WHILE section_begin_point < section_end_point LOOP

			--DBMS_OUTPUT.PUT_LINE('Iteration with: [BEGIN_POINT: ' || section_begin_point || '] [END_POINT: ' || section_end_point || ']');
			-- Split the section to what is left to be inserted
			remaining_section := SDO_LRS.CLIP_GEOM_SEGMENT(LRS_ROUTE, section_begin_point, section_end_point);

			-- Fetch the first overlapping segment of the segmented table
			BEGIN
				SELECT * INTO segment FROM 
					(SELECT * FROM ALFO_SEGMENTED
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

				--DBMS_OUTPUT.PUT_LINE('Result: No overlapping segment! Just insert the segment into the table!');

				INSERT INTO ALFO_SEGMENTED (OBJECTID, YEAR_RECOR, STATE_CODE, ROUTE_ID, BEG_POINT, END_POINT, SECTION_LE, COMMENTS, SHAPE)
		        VALUES (null, cursor.YEAR_RECOR, cursor.STATE_CODE, cursor.ROUTE_ID, section_begin_point, section_end_point, cursor.SECTION_LE, cursor.COMMENTS, SDO_LRS.CONVERT_TO_STD_GEOM(remaining_section));
		        
		        SELECT segmented_seq.CURRVAL INTO lastID FROM dual;
		        UPDATE_SEGMENTED_FIELD(lastID, cursor.DATA_ITEM, cursor.VALUE_NUME, cursor.VALUE_TEXT, cursor.VALUE_DATE);
				
		        --DBMS_OUTPUT.PUT_LINE('Inserted [ID: ' || lastID || '] [BEGIN_POINT: ' || section_begin_point || '] [END_POINT: ' || section_end_point || ']');
		        
				-- Set the begin point equal to the last point, so the loop will end at next round
				section_begin_point := section_end_point;

			-- The first segment found is further, we should only insert the first part of the section up to the beginning of the segment
			ELSIF segment.BEG_POINT > section_begin_point THEN

				--DBMS_OUTPUT.PUT_LINE('Result: The first segment found is further [BEGIN_POINT: ' || segment.BEG_POINT || ']!');

				remaining_section := SDO_LRS.CLIP_GEOM_SEGMENT(LRS_ROUTE, section_begin_point, segment.BEG_POINT);
				INSERT INTO ALFO_SEGMENTED (OBJECTID, YEAR_RECOR, STATE_CODE, ROUTE_ID, BEG_POINT, END_POINT, SECTION_LE, COMMENTS, SHAPE)
		        VALUES (null, cursor.YEAR_RECOR, cursor.STATE_CODE, cursor.ROUTE_ID, section_begin_point, segment.BEG_POINT, cursor.SECTION_LE, cursor.COMMENTS, SDO_LRS.CONVERT_TO_STD_GEOM(remaining_section));
		        
		        SELECT segmented_seq.CURRVAL INTO lastID FROM dual;
		        UPDATE_SEGMENTED_FIELD(lastID, cursor.DATA_ITEM, cursor.VALUE_NUME, cursor.VALUE_TEXT, cursor.VALUE_DATE);

		        --DBMS_OUTPUT.PUT_LINE('Inserted [ID: ' || lastID || '] [BEGIN_POINT: ' || section_begin_point || '] [END_POINT: ' || segment.BEG_POINT || ']');

				section_begin_point := segment.BEG_POINT;

			-- Trying to insert the section over a segment.
			ELSIF segment.BEG_POINT <= section_begin_point THEN
				--DBMS_OUTPUT.PUT_LINE('Result: Collision with an existing segment [OBJECTID: ' || segment.OBJECTID || '] [BEGIN_POINT: ' || segment.BEG_POINT || ']  [END_POINT: ' || segment.END_POINT || ']!');

				-- If both the section and the segment shares the same begin point
				IF segment.BEG_POINT = section_begin_point THEN
					--DBMS_OUTPUT.PUT_LINE('Result: Both the section and the section shares the begin point!');

					-- Segment and section are entirely overlapping
					IF section_end_point >= segment.END_POINT THEN
						--DBMS_OUTPUT.PUT_LINE('Result: Segment and section are entirely overlapping!');
						UPDATE_SEGMENTED_FIELD(segment.OBJECTID, cursor.DATA_ITEM, cursor.VALUE_NUME, cursor.VALUE_TEXT, cursor.VALUE_DATE);
						section_begin_point := segment.END_POINT;

					--  Segment and section are NOT entirely overlapping
					ELSIF section_end_point < segment.END_POINT THEN
						--DBMS_OUTPUT.PUT_LINE('Result: Segment and section are NOT entirely overlapping!');
						
						first_segment := SDO_LRS.CLIP_GEOM_SEGMENT(SDO_LRS.CONVERT_TO_LRS_GEOM(segment.SHAPE, segment.BEG_POINT, segment.END_POINT), section_begin_point, section_end_point);
						second_segment := SDO_LRS.CLIP_GEOM_SEGMENT(SDO_LRS.CONVERT_TO_LRS_GEOM(segment.SHAPE, segment.BEG_POINT, segment.END_POINT), section_end_point, segment.END_POINT);

						UPDATE ALFO_SEGMENTED SET
							OBJECTID = segmented_seq.NEXTVAL,
							END_POINT = section_end_point,
							SHAPE = SDO_LRS.CONVERT_TO_STD_GEOM(first_segment) WHERE OBJECTID = segment.OBJECTID;

						SELECT segmented_seq.CURRVAL INTO lastID FROM dual;
						UPDATE_SEGMENTED_FIELD(lastID, cursor.DATA_ITEM, cursor.VALUE_NUME, cursor.VALUE_TEXT, cursor.VALUE_DATE);
			      		
			     	 	--DBMS_OUTPUT.PUT_LINE('Updated [ID: ' || segment.OBJECTID || '] to [ID: ' || lastID || '] [BEGIN_POINT: ' || section_begin_point || '] [END_POINT: ' || section_end_point || ']');
			        
						segment.OBJECTID := null;
						segment.BEG_POINT := section_end_point;
						--segment.SHAPE :=  SDO_LRS.CONVERT_TO_LRS_GEOM(second_segment);
						INSERT INTO ALFO_SEGMENTED VALUES segment;

						SELECT segmented_seq.CURRVAL INTO lastID FROM dual;
						UPDATE ALFO_SEGMENTED SET SHAPE = SDO_LRS.CONVERT_TO_STD_GEOM(second_segment) WHERE OBJECTID = lastID;
						--DBMS_OUTPUT.PUT_LINE('Inserted [ID: ' || lastID || '] [BEGIN_POINT: ' || section_end_point || '] [END_POINT: ' || segment.END_POINT || ']');
						
						--TODO: UPDATE left side OF the segment

						section_begin_point := section_end_point;
					END IF;

				-- Section is a subset of the segment. Need to split up to section_begin_point and the next iteration will do the job.
				ELSE
					--DBMS_OUTPUT.PUT_LINE('Result: Section is a subset of the segment. Need to split up to section_begin_point and the next iteration will do the job.');

					first_segment := SDO_LRS.CLIP_GEOM_SEGMENT(SDO_LRS.CONVERT_TO_LRS_GEOM(segment.SHAPE, segment.BEG_POINT, segment.END_POINT), segment.BEG_POINT, section_begin_point);
					second_segment := SDO_LRS.CLIP_GEOM_SEGMENT(SDO_LRS.CONVERT_TO_LRS_GEOM(segment.SHAPE, segment.BEG_POINT, segment.END_POINT), section_begin_point, segment.END_POINT);

					UPDATE ALFO_SEGMENTED SET 
						OBJECTID = segmented_seq.NEXTVAL,
						END_POINT = section_begin_point,
						SHAPE = SDO_LRS.CONVERT_TO_STD_GEOM(first_segment) WHERE OBJECTID = segment.OBJECTID;

					SELECT segmented_seq.CURRVAL INTO lastID FROM dual;
		     	 	--DBMS_OUTPUT.PUT_LINE('Updated [ID: ' || segment.OBJECTID || '] to [ID: ' || lastID || '] [BEGIN_POINT: ' || segment.BEG_POINT || '] [END_POINT: ' || section_begin_point || ']');
		        
					segment.OBJECTID := null;
					segment.BEG_POINT := section_begin_point;
					--segment.SHAPE :=  SDO_LRS.CONVERT_TO_LRS_GEOM(second_segment);
					INSERT INTO ALFO_SEGMENTED VALUES segment;

					SELECT segmented_seq.CURRVAL INTO lastID FROM dual;
					UPDATE ALFO_SEGMENTED SET SHAPE = SDO_LRS.CONVERT_TO_STD_GEOM(second_segment) WHERE OBJECTID = lastID;
		      		--DBMS_OUTPUT.PUT_LINE('Inserted [ID: ' || lastID || '] [BEGIN_POINT: ' || section_begin_point || '] [END_POINT: ' || segment.END_POINT || ']');
		        

					
				END IF;
			END IF;   
		END LOOP;
		counter := counter + 1;
	    --IF counter > 500 THEN 
		--	goto end_proc;
		--END IF;
	END LOOP;
END;