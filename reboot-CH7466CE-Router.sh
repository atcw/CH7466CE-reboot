#!/bin/bash

# Reboot your Cable Gateway / Router
# For CBN - Compal Broadband Networks - CH7466CE - Wireless Voice Gateway - Firmware-Version  4.50.20.3 (above and earlier)
# Tested 2020-07-05 - with a German KabelDeutschlandGmbH(now Vodafone) provided (and probably customized) Router

# Weirdness explained
# A sessionToken is expected via Cookie AND ADDITIONALLY via urlencoded-form-data in the POST-Requests.
# The generation of session-tokens seems to be somewhat broken. Therefore this script makes use of waits and retries.
# The brokenness can even be observed with a GUI-browser as half-loaded pages with missing content.

# similar works (but incompatible with current versions):
# incompatible: https://github.com/enreda81/Compal-CG7486E/blob/master/restart.sh
# incompatible: https://github.com/leegianOS/CH7466CE-API/blob/master/src/main/java/de/linzn/cbn/api/ch7466ce/CBNApi.java

HOST="192.168.0.1"; #default ip
LOGINPASSWORD="password"; # is the actual default password
LOGINUSER="admin" #should never change

USERAGENT='User-Agent: Mozilla/4.0 (compatible; MSIE 4.01; Windows 95)'
SESSIONTOKEN="0" #broken token-generation provides 0

cookiejarfile=$(mktemp)
outputfile=$(mktemp)
tracefile=$(mktemp)

DEBUG=true #toggle some value
DEBUG=false #reboot

function retrieveToken #( )
{
	SESSIONTOKEN=$(awk '/sessionToken/ { print $7 }' ${cookiejarfile})
	echo "SESSIONTOKEN: " ${SESSIONTOKEN}
}

#function getrequest
#{
#	curl  -i \ # show response headers
#		-H "${USERAGENT}" \
#		--silent \ # no progress bar
#		--trace ${tracefile} \
#		--output ${outputfile} \ #no visible body output
#		--cookie ${cookiejarfile} \ #read
#		--cookie-jar  ${cookiejarfile} \ #write
#		--location \ #follow
#		--write-out "%{http_code}" \
#		"http://${HOST}/$1" 
#	#cat ${cookiejarfile}
#}

# Try until sessiontoken is properly generated. Requests are intentionally redundant.
until [ "${SESSIONTOKEN}" != "0" ]
do
	#follow location header #no --cookie ${cookiejarfile} yet.
	HTTPSTATUS=$(curl --silent -i -H "${USERAGENT}" --silent --trace ${tracefile} --output ${outputfile}  --cookie-jar  ${cookiejarfile} -L "http://${HOST}/" --write-out "%{http_code}" )
	retrieveToken
	echo Http-Status: $HTTPSTATUS
	#cat ${outputfile}
	sleep 1s
	### Login won't work without having requested "fun=3" before.
	HTTPSTATUS=$(curl --silent -i -H "${USERAGENT}" --trace ${tracefile} --output ${outputfile} --cookie ${cookiejarfile} --cookie-jar  ${cookiejarfile} "http://${HOST}/xml/getter.xml" -d "token=${SESSIONTOKEN}&fun=3"  --write-out "%{http_code}" -H 'Accept: application/xml, text/xml, */*; q=0.01' -H 'X-Requested-With: XMLHttpRequest' )
	
	
	sleep 1s
	HTTPSTATUS=$(curl --silent -i -H "${USERAGENT}" --silent --trace ${tracefile} --output ${outputfile} --cookie ${cookiejarfile} --cookie-jar ${cookiejarfile} "http://${HOST}/common_page/login.html" --write-out "%{http_code}" )
	retrieveToken
	
	
	if [ "${SESSIONTOKEN}" == "0" ]
		then
			echo waiting 5 sec because the sessiontoken is still bad
			sleep 5s
			#Get a large picture to trigger state change on the router.
			HTTPSTATUS=$(curl --silent -i -H "${USERAGENT}" --silent --trace ${tracefile} --output ${outputfile} --cookie ${cookiejarfile} --cookie-jar  ${cookiejarfile} -L "http://${HOST}/images/common_imgs/cbn_logo.png" --write-out "%{http_code}" )
			retrieveToken
			
	fi
	echo "About to test token"
done
echo "Token ok."

sleep 1s

#### Login ##### --trace ${tracefile} --output ${outputfile} --output loginfile.txt
HTTPSTATUS=$(curl -v -i --silent -H "${USERAGENT}" --trace ${tracefile} --output ${outputfile}  --cookie ${cookiejarfile} --cookie-jar ${cookiejarfile} "http://${HOST}/xml/setter.xml" -d "token=${SESSIONTOKEN}&fun=15&Username=${LOGINUSER}&Password=${LOGINPASSWORD}" --write-out "%{http_code}"   -H 'Accept: application/xml, text/xml, */*; q=0.01' -H 'X-Requested-With: XMLHttpRequest' )
retrieveToken

echo Http-Status: $HTTPSTATUS

# Often the reply is just empty. No Status-Code is returned either.
# i.e. no outputfile gets written. This is especially true when 
# no "Accept: application/xml ..." header is given with the request.

#Possible responses for Login-Request
#"KDGloginincorrect"
#"KDGchangePW;SID=599652352"
#"successful"

REPLYSIZE=$(stat -c%s "${outputfile}")
if [ "${REPLYSIZE}" -gt "1000" ] # We are being 302'ed and receive the full index.html.
then
	echo "Can't login. There is a preexisting active session. Please wait for it to expire."
	exit -1
fi
	
if grep -q -e successful -e KDGchangePW ${outputfile};
then
	echo "Login successful"
else
	echo "Login failed. Reason:"
	cat ${outputfile}
	#cat ${tracefile}

	exit -1
fi

### If password was not yet changed from default on router, 'SID' needs to be extracted and put into the cookiejarfile.
if grep -q -e KDGchangePW ${outputfile};
then
	echo "Password not changed from default."
	#KDGchangePW;SID=599652352
	regex=';SID=([0-9]*)'
	reply=$(cat ${outputfile})
	[[ "$reply" =~ $regex ]]
	echo "Found:"
	echo "${BASH_REMATCH[1]}"
	#append to Netscape-style cookiejarfile
	echo "${HOST}\tFALSE\t/\tFALSE\t0\tSID\t${BASH_REMATCH[1]}">>${cookiejarfile}
fi
	

if $DEBUG #toggle Telefony>Configuration>ShowDateAndTimeForCallerID
then
	#Result can be observed on http://${routerip}/voip_page/CbnMtaConfiguration.html
	echo "Toggling Telefony>Configuration>ShowDateAndTimeForCallerID"
	
	sleep 1s
	HTTPSTATUS= curl  -i --silent -H "${USERAGENT}" --trace ${tracefile} --output ${outputfile} --cookie ${cookiejarfile} --cookie-jar ${cookiejarfile} "http://${HOST}/xml/getter.xml" -d "token=${SESSIONTOKEN}&fun=508" --write-out "%{http_code}" -H 'Accept: application/xml, text/xml, */*; q=0.01' -H 'X-Requested-With: XMLHttpRequest' 
	retrieveToken
	reply=$(cat ${outputfile})
	echo $reply
	echo "Endreply"
	regex='<DateAndTimeEnable>([0-9])</DateAndTimeEnable>'
	[[ "$reply" =~ $regex ]]
	echo "Found:"
	echo "${BASH_REMATCH[1]}"
	toggleenable=${BASH_REMATCH[1]}
	#invert
	[ $toggleenable = "0" ] && toggleenable="1" || toggleenable="0";
	sleep 1s
	HTTPSTATUS= curl --silent -i -H "${USERAGENT}" --trace ${tracefile} --output ${outputfile} --cookie ${cookiejarfile} --cookie-jar ${cookiejarfile} "http://${HOST}/xml/setter.xml" -d "token=${SESSIONTOKEN}&fun=509&Enable=${toggleenable}" --write-out "%{http_code}"   -H 'Accept: application/xml, text/xml, */*; q=0.01' -H 'X-Requested-With: XMLHttpRequest'  
	retrieveToken
	
	#Logout
	HTTPSTATUS= curl --silent -i -H "${USERAGENT}" --trace ${tracefile} --output ${outputfile} --cookie ${cookiejarfile} --cookie-jar ${cookiejarfile} "http://${HOST}/xml/setter.xml" -d "token=${SESSIONTOKEN}&fun=16" --write-out "%{http_code}"   -H 'Accept: application/xml, text/xml, */*; q=0.01' -H 'X-Requested-With: XMLHttpRequest'  
	retrieveToken
fi

if  ! $DEBUG #Reboot
then
	echo "Sending Reboot Command"
	sleep 1s
	HTTPSTATUS= curl --silent -i -H "${USERAGENT}" --trace ${tracefile} --cookie ${cookiejarfile} --cookie-jar ${cookiejarfile} "http://${HOST}/xml/setter.xml" -d "token=${SESSIONTOKEN}&fun=8" --write-out "%{http_code}"   -H 'Accept: application/xml, text/xml, */*; q=0.01' -H 'X-Requested-With: XMLHttpRequest'  
	retrieveToken
fi

rm -f ${cookiejarfile}
rm -f ${outputfile}
rm -f ${tracefile}
