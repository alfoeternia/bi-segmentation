create or replace PROCEDURE HPMS_SEG_CAPACITY_PROC
AS
	debug_file UTL_FILE.FILE_TYPE;
  
 	routeID VARCHAR2(50); -- Temporary

	section_begin_point NUMBER(7,3);
	section_end_point NUMBER(7,3);

	LRS_ROUTE ALFO_TEST.shape%TYPE;

	segment HPMS_SEG_CAPACITY%ROWTYPE;
	remaining_section ALFO_TEST.shape%TYPE;

	first_segment HPMS_SEG_CAPACITY.geometry%TYPE;
	second_segment HPMS_SEG_CAPACITY.geometry%TYPE;

	currentID NUMBER := 0;
BEGIN

debug_file := UTL_FILE.FOPEN ('TEST_ALFO_DIR', 'HPMS_SEG_CAPACITY.txt', 'W');

FOR cursor2 IN (select ROUTE_ID from hpms_section group by route_id order by count(route_id) desc) LOOP
	routeID := cursor2.ROUTE_ID;
  
	-- Loop over each segment of a same road
	FOR cursor IN (SELECT * FROM HPMS_SECTION HPMS WHERE HPMS.ROUTE_ID = routeID AND HPMS.SHAPE.SDO_GTYPE = 2002 AND HPMS.DATA_ITEM IN ('AADT', 'PCT_PEAK_COMBINATION', 'PCT_PEAK_SINGLE', 'PCT_PASS_SIGHT', 'K_FACTOR', 'DIR_FACTOR', 'SHOULDER_WIDTH_L', 'SHOULDER_WIDTH_R', 'SPEED_LIMIT', 'TERRAIN_TYPE', 'THROUGH_LANES', 'URBAN_CODE', 'FACILITY_TYPE', 'ACCESS_CONTROL', 'LANE_WIDTH', 'MEDIAN_WIDTH', 'SHOULDER_TYPE', 'F_SYSTEM', 'SIGNAL_TYPE', 'PCT_GREEN_TIME', 'NUMBER_SIGNALS', 'STOP_SIGNS', 'COUNTY_CODE', 'PEAK_LANES', 'TURN_LANES_L', 'TURN_LANES_R', 'PEAK_PARKING', 'AT_GRADE_OTHER')) LOOP
		
		section_begin_point := cursor.BEG_POINT;
		section_end_point := cursor.END_POINT;

		-- SDO_GEOMETRY (Shape) is converted to LRS Geometry
		LRS_ROUTE := SDO_LRS.CONVERT_TO_LRS_GEOM(cursor.SHAPE, cursor.BEG_POINT, cursor.END_POINT);

		UTL_FILE.PUT_LINE (debug_file, '-----------------------------------------');
		UTL_FILE.PUT_LINE (debug_file, 'Processing segment #' || cursor.OBJECTID || '...');
		UTL_FILE.PUT_LINE (debug_file, 'Start/End Point: ' || cursor.BEG_POINT || ' -> ' || cursor.END_POINT);
		UTL_FILE.PUT_LINE (debug_file, 'Length: ' || (SDO_LRS.GEOM_SEGMENT_END_MEASURE(LRS_ROUTE) - SDO_LRS.GEOM_SEGMENT_START_MEASURE(LRS_ROUTE)));
		UTL_FILE.FFLUSH(debug_file);

		-- While the segment has not been entirely processed
		WHILE section_begin_point < section_end_point LOOP

			UTL_FILE.PUT_LINE (debug_file, 'Iteration with: [BEGIN_POINT: ' || section_begin_point || '] [END_POINT: ' || section_end_point || ']');

			-- Split the section to what is left to be inserted
			remaining_section := SDO_LRS.CLIP_GEOM_SEGMENT(LRS_ROUTE, section_begin_point, section_end_point);

			-- Fetch the first overlapping segment of the segmented table
			BEGIN
				SELECT * INTO segment FROM 
					(SELECT * FROM HPMS_SEG_CAPACITY
					WHERE ROUTE_ID = routeID
						AND (BEG_POINT <= section_end_point AND END_POINT > section_begin_point)
					ORDER BY BEG_POINT)
				WHERE ROWNUM = 1;



				EXCEPTION
				WHEN NO_DATA_FOUND THEN
					segment.OBJECTID := NULL;
			END;

			-- No segment is found, then simply insert the full section to the table
			IF segment.OBJECTID IS NULL THEN

				UTL_FILE.PUT_LINE (debug_file, 'Result: No overlapping segment! Just insert the segment into the table!');

				INSERT INTO HPMS_SEG_CAPACITY (OBJECTID, YEAR_RECOR, STATE_CODE, ROUTE_ID, BEG_POINT, END_POINT, SECTION_LE, COMMENTS, GEOMETRY)
				VALUES (currentID, cursor.YEAR_RECOR, cursor.STATE_CODE, cursor.ROUTE_ID, section_begin_point, section_end_point, cursor.SECTION_LE, cursor.COMMENTS, SDO_LRS.CONVERT_TO_STD_GEOM(remaining_section));
				
				UPDATE_SEGMENTED_FIELD(currentID, cursor.DATA_ITEM, cursor.VALUE_NUME, cursor.VALUE_TEXT, cursor.VALUE_DATE);
				
				UTL_FILE.PUT_LINE (debug_file, 'Inserted [ID: ' || currentID || '] [BEGIN_POINT: ' || section_begin_point || '] [END_POINT: ' || section_end_point || ']');
				
				-- Set the begin point equal to the last point, so the loop will end at next round
				currentID := currentID + 1;
				section_begin_point := section_end_point;

			-- The first segment found is further, we should only insert the first part of the section up to the beginning of the segment
			ELSIF segment.BEG_POINT > section_begin_point THEN

				UTL_FILE.PUT_LINE (debug_file, 'Result: The first segment found is further [BEGIN_POINT: ' || segment.BEG_POINT || ']!');

				remaining_section := SDO_LRS.CLIP_GEOM_SEGMENT(LRS_ROUTE, section_begin_point, segment.BEG_POINT);
				INSERT INTO HPMS_SEG_CAPACITY (OBJECTID, YEAR_RECOR, STATE_CODE, ROUTE_ID, BEG_POINT, END_POINT, SECTION_LE, COMMENTS, GEOMETRY)
				VALUES (currentID, cursor.YEAR_RECOR, cursor.STATE_CODE, cursor.ROUTE_ID, section_begin_point, segment.BEG_POINT, cursor.SECTION_LE, cursor.COMMENTS, SDO_LRS.CONVERT_TO_STD_GEOM(remaining_section));
				
				UPDATE_SEGMENTED_FIELD(currentID, cursor.DATA_ITEM, cursor.VALUE_NUME, cursor.VALUE_TEXT, cursor.VALUE_DATE);

				UTL_FILE.PUT_LINE (debug_file, 'Inserted [ID: ' || currentID || '] [BEGIN_POINT: ' || section_begin_point || '] [END_POINT: ' || segment.BEG_POINT || ']');

				currentID := currentID + 1;
				section_begin_point := segment.BEG_POINT;

			-- Trying to insert the section over a segment.
			ELSIF segment.BEG_POINT <= section_begin_point THEN
				UTL_FILE.PUT_LINE (debug_file, 'Result: Collision with an existing segment [OBJECTID: ' || segment.OBJECTID || '] [BEGIN_POINT: ' || segment.BEG_POINT || ']  [END_POINT: ' || segment.END_POINT || ']!');

				-- If both the section and the segment shares the same begin point
				IF segment.BEG_POINT = section_begin_point THEN
					UTL_FILE.PUT_LINE (debug_file, 'Result: Both the section and the section shares the begin point!');

					-- Segment and section are entirely overlapping
					IF section_end_point >= segment.END_POINT THEN
						UTL_FILE.PUT_LINE (debug_file, 'Result: Segment and section are entirely overlapping!');
						UPDATE_SEGMENTED_FIELD(segment.OBJECTID, cursor.DATA_ITEM, cursor.VALUE_NUME, cursor.VALUE_TEXT, cursor.VALUE_DATE);
						section_begin_point := segment.END_POINT;

					--  Segment and section are NOT entirely overlapping
					ELSIF section_end_point < segment.END_POINT THEN
						UTL_FILE.PUT_LINE (debug_file, 'Result: Segment and section are NOT entirely overlapping!');
						
						first_segment := SDO_LRS.CLIP_GEOM_SEGMENT(SDO_LRS.CONVERT_TO_LRS_GEOM(segment.GEOMETRY, segment.BEG_POINT, segment.END_POINT), section_begin_point, section_end_point);
						second_segment := SDO_LRS.CLIP_GEOM_SEGMENT(SDO_LRS.CONVERT_TO_LRS_GEOM(segment.GEOMETRY, segment.BEG_POINT, segment.END_POINT), section_end_point, segment.END_POINT);

						UPDATE HPMS_SEG_CAPACITY SET
							OBJECTID = currentID,
							END_POINT = section_end_point,
							GEOMETRY = SDO_LRS.CONVERT_TO_STD_GEOM(first_segment) WHERE OBJECTID = segment.OBJECTID;

						UPDATE_SEGMENTED_FIELD(currentID, cursor.DATA_ITEM, cursor.VALUE_NUME, cursor.VALUE_TEXT, cursor.VALUE_DATE);
				  		
				 	 	UTL_FILE.PUT_LINE (debug_file, 'Updated [ID: ' || segment.OBJECTID || '] to [ID: ' || currentID || '] [BEGIN_POINT: ' || section_begin_point || '] [END_POINT: ' || section_end_point || ']');
						currentID := currentID + 1;
					
						segment.OBJECTID := currentID;
						segment.BEG_POINT := section_end_point;

						INSERT INTO HPMS_SEG_CAPACITY VALUES segment;

						UPDATE HPMS_SEG_CAPACITY SET GEOMETRY = SDO_LRS.CONVERT_TO_STD_GEOM(second_segment) WHERE OBJECTID = currentID;
						UTL_FILE.PUT_LINE (debug_file, 'Inserted [ID: ' || currentID || '] [BEGIN_POINT: ' || section_end_point || '] [END_POINT: ' || segment.END_POINT || ']');

						currentID := currentID + 1;
						section_begin_point := section_end_point;
					END IF;

				-- Section is a subset of the segment.
				-- Need to split up to section_begin_point and the next iteration will do the job.
				ELSE
					UTL_FILE.PUT_LINE (debug_file, 'Result: Section is a subset of the segment. Need to split up to section_begin_point and the next iteration will do the job.');

					first_segment := SDO_LRS.CLIP_GEOM_SEGMENT(SDO_LRS.CONVERT_TO_LRS_GEOM(segment.GEOMETRY, segment.BEG_POINT, segment.END_POINT), segment.BEG_POINT, section_begin_point);
					second_segment := SDO_LRS.CLIP_GEOM_SEGMENT(SDO_LRS.CONVERT_TO_LRS_GEOM(segment.GEOMETRY, segment.BEG_POINT, segment.END_POINT), section_begin_point, segment.END_POINT);


					UPDATE HPMS_SEG_CAPACITY SET 
						OBJECTID = currentID,
						END_POINT = section_begin_point,
						GEOMETRY = SDO_LRS.CONVERT_TO_STD_GEOM(first_segment) WHERE OBJECTID = segment.OBJECTID;

			 	 	UTL_FILE.PUT_LINE (debug_file, 'Updated [ID: ' || segment.OBJECTID || '] to [ID: ' || currentID || '] [BEGIN_POINT: ' || segment.BEG_POINT || '] [END_POINT: ' || section_begin_point || ']');
					currentID := currentID + 1;
				

					segment.OBJECTID := null;
					segment.BEG_POINT := section_begin_point;
					INSERT INTO HPMS_SEG_CAPACITY VALUES segment;

					UPDATE HPMS_SEG_CAPACITY SET GEOMETRY = SDO_LRS.CONVERT_TO_STD_GEOM(second_segment) WHERE OBJECTID = currentID;
			  		UTL_FILE.PUT_LINE (debug_file, 'Inserted [ID: ' || currentID || '] [BEGIN_POINT: ' || section_begin_point || '] [END_POINT: ' || segment.END_POINT || ']');
					currentID := currentID + 1;
				
					
				END IF;
			END IF;   
		END LOOP;
	COMMIT;
	END LOOP;
END LOOP;
END;