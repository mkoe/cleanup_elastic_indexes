#!/bin/bash



########## Configurationsection ##########
# In case of an error, who should receive the email
MAILTO="PROVIDE EMAILADDRESSE"
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
# Turn on debug informations
DEBUG=0
DIR_INDEX="/tmp"
LOCK_DIR="/var/run"
FILE_TMP="${DIR_INDEX}/manage_elastic_tmp"
FILE_EXE="${DIR_INDEX}/managelastic"
FILE_INDEX="${DIR_INDEX}/indexes"
ALL_INDEX="${DIR_INDEX}/all_indexes"
ERROR_FILE="/tmp/elasticerror"
# Put Here your Elasticserver
ELASTICSERVER="PUT ELASTICSERVER HERE"
ELASTICPORT="PUT ELASTICSERVERPORT HERE"
#Put here all your indices which need to be ignored by this script, seperated by | 
IGNORE_INDICES="\.[a-zA-Z]"
# How many days an index should remain open before closing it
CLOSE_AFTER_DAYS=$(($(date -d "4 days ago" +%s) * 1000))
# How man days an index should remain close before it will get deleted
DELETE_AFTER_DAYS=$(($(date -d "7 days ago" +%s) * 1000))
########### End of Configuration ###########

> ${FILE_EXE}
> ${FILE_TMP}
> ${ERROR_FILE}

# this script will clean up all left overs

function log_error () {

	echo $1 >> ${ERROR_FILE}
}

function debug () {

	if [[ ${DEBUG} -gt 0 ]]
	then
		echo $1
	fi

}

function mail_error {
	mail -s "script $0 was executed with errors on host $(hostname)" ${MAILTO} < ${ERROR_FILE}
}


for PROGRAM in bc jq curl awk
do
      debug "Checking existing of Program: ${PROGRAM}";
      if ( ! $(which ${PROGRAM} > /dev/null 2>&1) )
      then
              echo "Please install ${PROGRAM}";
              log_error "Please install ${PROGRAM}";
              BREAK=1
      else
              debug "Program ${PROGRAM} seems to be installed"
      fi
done

if [[ ${BREAK} -gt 0 ]]
then
      echo "Aborting execution, because of failed dependecies"
      exit ${BREAK}
fi

if [[ ! -e ${LOCK_DIR}/cleanup_elastic.lock ]]
then
	touch ${LOCK_DIR}/cleanup_elastic.lock
	curl -s http://${ELASTICSERVER}:${ELASTICPORT}/_cat/indices?v  > ${FILE_INDEX}
	curl -s http://${ELASTICSERVER}:${ELASTICPORT}/_all > ${ALL_INDEX}
	for i in $( awk '/open/{print $3}' ${FILE_INDEX} | grep -v -E "${IGNORE_INDICES}")
	do
		INDEX_DATE=$(jq -c  "( .\"${i}\".settings.index.creation_date  | tonumber )" ${ALL_INDEX})
		CORRECT_DATE=$(echo ${INDEX_DATE} / 1000 | bc)
		if [[ ${INDEX_DATE} -lt ${CLOSE_AFTER_DAYS} ]]
		then
			debug "Will need to close ${i} because it was created $(date -d @${CORRECT_DATE})"
			HTTP_RESP=$(curl -w "%{http_code}" -o /dev/null -s -XPOST http://${ELASTICSERVER}:${ELASTICPORT}/${i}/_close)
			if [[ ${HTTP_RESP} -gt 200 ]] && [[ ${HTTP_RESP} -ne 404 ]]
			then
				log_error "Closing index ${i} failed with Errorcode:  ${HTTP_RESP}"
			fi
		else
			debug "Will remain open ${i} because it was created $(date -d @${CORRECT_DATE})"
		fi
		
	done
	
	# we will need to get all closed indexes creationdates, because they are not included within the /_all query
	for i in $( awk '/close/{print $2}' ${FILE_INDEX} | grep -v -E "${IGNORE_INDICES}")
	do
	    INDEX_DATE=$(curl -s http://${ELASTICSERVER}:${ELASTICPORT}/${i} | jq -c  "( .[].settings.index.creation_date  | tonumber )")
		CORRECT_DATE=$(echo ${INDEX_DATE} / 1000 | bc)
		if [[ ${INDEX_DATE} -lt ${DELETE_AFTER_DAYS} ]] 
		then
			debug "Will need to delete ${i} because it was created $(date -d @${CORRECT_DATE})"
			HTTP_RESP=$(curl -s -w "%{http_code}" -o /dev/null -XDELETE http://${ELASTICSERVER}:${ELASTICPORT}/${i})
			HTTP_TEMP_RESP=$(curl -w "%{http_code}" -o /dev/null -s -XDELETE http://${ELASTICSERVER}:${ELASTICPORT}/_template/${i})
			if [[ ${HTTP_RESP} -gt 200 ]]  && [[ ${HTTP_RESP} -ne 404 ]]
			then
				log_error "Deleting index ${i} failed with Errorcode: ${HTTP_RESP}"
			fi
			if [[ ${HTTP_TEMP_RESP} -gt 200 ]] && [[ ${HTTP_TEMP_RESP} -ne 404 ]]
			then
				log_error "Deleting Template ${i} failed with Errorcode: ${HTTP_TEMP_RESP}"
			fi
		else
			debug "${i}  remain on Store because it was created $(date -d @${CORRECT_DATE})"
		fi
	done
	rm ${LOCK_DIR}/cleanup_elastic.lock
else
	log_error "Lockfile exists. Please remove ${LOCK_DIR}/cleanup_elastic.lock and check your Mails"
fi

if [[ -s ${ERROR_FILE} ]]
then
	mail_error
fi
