#!/bin/bash
#########################################
# Script to check DataCache content size
#########################################

### Debug
# set -x

### Variables
APP_HOST=()
APP_PORT=(10117 10147)
DELTA_ETALON=4000
MAIL_TO=""
DOMAIN=""

##################################################
### Function to curl cachemonitor URL
### Accepts below parameters:
### $1 -> ${HOST}
### $2 -> ${PORT}
###################################################
cachemon_curl () {
           #to fix zero results returned by statistics.jsp
           # short curl keys: -b, --cookie; -c, --cookie-jar
           RESP_CODE=$(curl --cookie cookie.xml --cookie-jar cookie-jar.xml --write-out '%{http_code}' --silent --output /dev/null https://$1.${DOMAIN}:$2/cachemonitor/selectInstance.jsp?instance=baseCache)
           ENTRY_SIZE=$(curl -b cookie.xml -c cookie.xml -s https://$1.${DOMAIN}:$2/cachemonitor/statistics.jsp? | grep "Cache Size" -A1 | tail -n 1 | grep -Po '.*<td class="description-text">\K[[:digit:]]*');

           echo "Host: $1 Port: $2 Response_code: ${RESP_CODE} Cache_entry_size: ${ENTRY_SIZE}"
}

##################################################
### Function to compare DataCache entries size
###################################################
comp_datacache_size () {

   # variables
   PREV_SIZE=0

   # per host
   for HOST in ${APP_HOST[@]};
   do

     # per port
     for PORT in ${APP_PORT[@]};
     do
        # for all iterations except fisrts
        if [[ ${PREV_SIZE} -ne 0 ]];
        then

           cachemon_curl ${HOST} ${PORT}

           if [[ ! -z ${ENTRY_SIZE} ]];
           then

             # Calculate DELTA_SIZE to override negative integers
             if [ ${ENTRY_SIZE} -ge ${PREV_SIZE} ];
             then
                DELTA_SIZE=$((${ENTRY_SIZE}-${PREV_SIZE}))

             elif [ ${PREV_SIZE} -gt ${ENTRY_SIZE} ];
             then
                DELTA_SIZE=$((${PREV_SIZE}-${ENTRY_SIZE}))

             fi

             # Generate error array
             if [ ${DELTA_SIZE} -gt ${DELTA_ETALON} ];
             then
                ARR_ERROR+=("https://${HOST}.${DOMAIN}:${PORT}/cachemonitor Error:Cache_entry_size:${ENTRY_SIZE}");
             fi

          fi

        # for first iteration
        else

           cachemon_curl ${HOST} ${PORT}

           PREV_SIZE=${ENTRY_SIZE}
        fi

     done

   if [[ ! -z ${ENTRY_SIZE} ]];
   then
      PREV_SIZE=${ENTRY_SIZE}
   else
      ARR_ERROR+=("https://${HOST}.${DOMAIN}:${PORT}/cachemonitor Error:Cannot_connect_to_cachemonitor")
   fi
   done

}

##################################################
### Function to sent email
##################################################
send_email () {

   # variable
   BODY=""

   # if ${ARR_ERROR[@]} no zero size
   if [ ${#ARR_ERROR[@]} -ge 1 ];
   then

       echo "Errors found. Sending email..."

       for ERROR in ${ARR_ERROR[@]};
       do
          BODY="${BODY}${ERROR}\n"
       done

       echo -e "${BODY}" | /bin/mailx -s "PROD: DataCache entries differs" ${MAIL_TO}
   else

      echo "No errors found!"

   fi
}

#########################################
###              MAIN                 ###
#########################################
comp_datacache_size
send_email
