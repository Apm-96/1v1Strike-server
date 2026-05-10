#!/bin/bash

LOG_DIR="/xashds/cstrike/logs"
DEST="/xashds/saved_logs"

if [ -z "$DISCORD_URL" ]; then
    echo "Error: La variable DISCORD_URL no està definida."
    exit 1
fi

mkdir -p "$DEST"
echo "--- MONITOR ACTIU ---"

inotifywait -m -e create --format "%f" "$LOG_DIR" | while read NEW_FILE
do
    COUNT=$(ls -1 "$LOG_DIR" | wc -l)

    if [ "$COUNT" -eq 3 ]; then
        sleep 3
        TARGET_LOG=$(ls -tr "$LOG_DIR" | sed -n '2p')
        FULL_PATH="$LOG_DIR/$TARGET_LOG"

        if [ -f "$FULL_PATH" ]; then
            cp "$FULL_PATH" "$DEST/$TARGET_LOG"
	    # EXTRACCIÓ DE DADES
            FILE="$DEST/$TARGET_LOG"
            DATA=$(grep "Log file started" "$FILE" | cut -d' ' -f1)
	    
            # Extraiem l'hora MANTENINT els ":" pel càlcul de 'date'
            HORA_INICI=$(grep "Log file started" "$FILE" | cut -d' ' -f3)
            HORA_FINAL=$(grep "Log file closed" "$FILE" | cut -d' ' -f3)

            # Si no hi ha línia de tancament, agafem l'hora de l'última línia del log
            if [ -z "$HORA_FINAL" ]; then
                HORA_FINAL=$(tail -n 1 "$FILE" | cut -d' ' -f3)
            fi

            # Càlcul de durada (important: treure el caràcter ':' final si el grep l'ha agafat)
            H_INICI_NET=$(echo $HORA_INICI | tr -d ':')
            H_FINAL_NET=$(echo $HORA_FINAL | tr -d ':')

            # Convertim a segons (usant el format HH:MM:SS que 'date' entén)
            SEC_INICI=$(date -d "${HORA_INICI%:}" +%s)
            SEC_FINAL=$(date -d "${HORA_FINAL%:}" +%s)
            DIFF_SEC=$((SEC_FINAL - SEC_INICI))
            
            DURADA="$((DIFF_SEC / 60)) min $((DIFF_SEC % 60)) seg"

            # Mapa i Jugadors i dades
            MAPA=$(grep "Loading map" "$FILE" | head -n 1 | sed 's/.*"\(.*\)".*/\1/')
            P_T=$(grep "joined team \"TERRORIST\"" "$FILE" | head -n 1 | sed 's/[^"]*"\([^"]*\)".*/\1/')
            P_CT=$(grep "joined team \"CT\"" "$FILE" | head -n 1 | sed 's/[^"]*"\([^"]*\)".*/\1/')
	    P_T_Name=$(echo "$P_T" | sed 's/<.*//')
	    P_CT_Name=$(echo "$P_CT" | sed 's/<.*//')
            KILLS_T=$(grep -c "\"${P_T_Name}.*<TERRORIST>\" killed" "$FILE")
            KILLS_CT=$(grep -c "\"${P_CT_Name}.*<CT>\" killed" "$FILE")
	    DEATHS_T_OLD=$(($(grep -c "\"$P_T_Name<.*>.*committed suicide" "$FILE") + KILLS_CT))
	    DEATHS_CT_OLD=$(($(grep -c "\"$P_CT_Name<.*>.*committed suicide" "$FILE") + KILLS_T))

	    SUICIDE_T=$(perl -0777 -ne 'BEGIN {$t = shift; $count = 0;};while (/End"\n[^"]*"\Q$t\E[^"]*" committed/gm) {$count++;}print $count;' "$P_T_Name" "$FILE")
	    SUICIDE_CT=$(perl -0777 -ne 'BEGIN {$ct = shift; $count = 0;}while (/End"\n[^"]*"\Q$ct\E[^"]*" committed/gm) {$count++;}print $count;' "$P_CT_Name" "$FILE")
            EARLY_T=$(perl -0777 -ne 'BEGIN {$t = shift;}if (/\Q$t\E[^"]*" committed.*"Game_Commencing"/sm) {print "1";} else {print "0";}' "$P_T_Name" "$FILE")
	    EARLY_CT=$(perl -0777 -ne 'BEGIN{$ct = shift};if (/\Q$ct\E[^"]*" committed.*"Game_Commencing"/sm) {print "1";} else {print "0";}' "$P_CT_Name" "$FILE")
	    DEATHS_T=$((DEATHS_T_OLD-SUICIDE_T-EARLY_T))
	    DEATHS_CT=$((DEATHS_CT_OLD-SUICIDE_CT-EARLY_CT))

	    # Extreure puntuacions (busquem l'última referència de puntuació al log)
	    SCORE_CT=$(grep "Team \"CT\" scored" "$FILE" | tail -n 1 | sed 's/.*scored "\([0-9]*\)".*/\1/')
	    SCORE_T=$(grep "Team \"TERRORIST\" scored" "$FILE" | tail -n 1 | sed 's/.*scored "\([0-9]*\)".*/\1/')
	    
	    # Si no es troba puntuació al log, posem 0 per defecte
	    [ -z "$SCORE_CT" ] && SCORE_CT=0
	    [ -z "$SCORE_T" ] && SCORE_T=0
	    
	    # Si ningú ha arribat a 10, el score és "null"
	    if [ "$SCORE_CT" -lt 10 ] && [ "$SCORE_T" -lt 10 ]; then
	        SCORE_DISPLAY="null"
	        WINNER="None (Incomplete)"
	    else
	        SCORE_DISPLAY="${SCORE_CT}-${SCORE_T}"
    	    
	        # Ja que estem, podem validar el WINNER basant-nos en el score real
    	        if [ "$SCORE_CT" -ge 10 ]; then
                    WINNER="$P_CT_Name"
	        else
	            WINNER="$P_T_Name"
	        fi
	    fi
            # CONSTRUCCIÓ DEL MISSATGE
            RESUM="Data: $DATA\nInici: ${HORA_INICI%:}\nDurada: $DURADA\nMapa: $MAPA\nScore: $SCORE_DISPLAY\n$P_CT_Name: $KILLS_CT kills, $DEATHS_CT deaths\n$P_T_Name: $KILLS_T kills, $DEATHS_T deaths\nWinner: $WINNER"
	    echo "aaa $DEATHS_T_OLD aaa $DEATHS_CT_OLD aaa $DEATHS_T aaa $DEATHS_CT aaa $SUICIDE_T aaa $SUICIDE_CT aaa $EARLY_T aaa $EARLY_CT aaa $WINNER"
            # ENVIAMENT
            curl -H "Content-Type: multipart/form-data" \
                 -F "file=@$FILE" \
                 -F "payload_json={\"content\": \"**Partida Finalitzada!**\n\`\`\`\n$RESUM\n\`\`\`\"}" \
                 "$DISCORD_URL"
            echo "Enviat: $TARGET_LOG"
            #Sayonara baby
            NOM_NET=$(echo "$MAPA" | cut -d'_' -f2)
            echo "Partida acabada al mapa $MAPA. Avisant al controller per tancar xash-$NOM_NET..."
	    # Cridem al Controller de la màquina host
            curl -X POST "http://192.168.1.114:5000/detenir-servidor/$NOM_NET"
        fi
    fi
done
