#!/bin/bash

# Reboot your Cable Gateway / Router
# For CBN - Compal Broadband Networks - CH7466CE - Wireless Voice Gateway - Firmware-Version  4.50.20.3 (above and earlier)
# Tested 2020-07-05

# sessionToken is expected via Cookie AND ADDITIONALLY via urlencoded-form-data in the POST-Requests
# The SessionToken-Generation seems to be somewhat broken. Therefore this script makes use of waits and retries.
# This can be observed with a GUI-browser as half-loaded pages with missing content.



HOST="192.168.0.1"; #default ip
LOGINPASSWORD="password"; # is the actual default password
LOGINUSER="admin" #should never change


USERAGENT='User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/83.0.4103.116 Safari/537.36'
USERAGENT='User-Agent: Mozilla/4.0 (compatible; MSIE 4.01; Windows 95)'
SESSIONTOKEN="0"

cookiejarfile=$(mktemp)
outputfile=$(mktemp)
tracefile=$(mktemp)


DEBUG=false
DEBUG=true

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
#		"http://${HOST}/$1" 
#	#cat ${cookiejarfile}
#}

# Try until sessiontoken is properly generated. Requests are intentionally redundant.
until [ "${SESSIONTOKEN}" != "0" ]
do
	#follow location header #no --cookie ${cookiejarfile} yet.
	curl  -i -H "${USERAGENT}" --silent --trace ${tracefile} --output ${outputfile}  --cookie-jar  ${cookiejarfile} -L "http://${HOST}/" #&& cat ${cookiejarfile}
	retrieveToken
	
	#cat ${outputfile}
	sleep 1s
	### Login won't work without having requested "fun=3" before.
	curl  -i -H "${USERAGENT}" --trace ${tracefile} --output ${outputfile} --cookie ${cookiejarfile} --cookie-jar  ${cookiejarfile} "http://${HOST}/xml/getter.xml" -d "token=${SESSIONTOKEN}&fun=3" 
	
	
	sleep 1s
	curl -i -H "${USERAGENT}" --silent --trace ${tracefile} --output ${outputfile} --cookie ${cookiejarfile} --cookie-jar ${cookiejarfile} "http://${HOST}/common_page/login.html"
	retrieveToken
	
	
	if [ "${SESSIONTOKEN}" == "0" ]
		then
			echo waiting 5 sec because the sessiontoken is still bad
			sleep 5s
			#Get a large picture to trigger state change on the router.
			curl -i -H "${USERAGENT}" --silent --trace ${tracefile} --output ${outputfile} --cookie ${cookiejarfile} --cookie-jar  ${cookiejarfile} -L "http://${HOST}/images/common_imgs/cbn_logo.png" && cat ${cookiejarfile}
			retrieveToken
			
	fi
	echo "About to test token"
done
echo "Token ok."

sleep 1s

#### Login ##### --trace ${tracefile} --output ${outputfile} --output loginfile.txt
curl  -v -i  -H "${USERAGENT}"   --cookie ${cookiejarfile} --cookie-jar ${cookiejarfile} "http://${HOST}/xml/setter.xml" -d "token=${SESSIONTOKEN}&fun=15&Username=${LOGINUSER}&Password=${LOGINPASSWORD}" -w "\n\n%{http_code}\n"   -H 'Accept: application/xml, text/xml, */*; q=0.01' -H 'X-Requested-With: XMLHttpRequest'  
retrieveToken

# Often the reply is just empty. No Status-Code is returned either.
# i.e. no outputfile gets written, especially when 
# no "Accept: application/xml" header is given with the request.

#Possible responses
#"KDGloginincorrect"
#"KDGchangePW;SID=599652352"
#"successful"

	#cat ${outputfile}
	#cat ${tracefile}
REPLYSIZE=$(stat -c%s "${outputfile}")
if [ ${REPLYSIZE} -gt 1000 ] # We are being 302'ed.
then
	echo "Can't login. There is a preexisting active session."
	exit -1
fi
	
if grep -q -e successful -e KDGchangePW ${outputfile};
then
	echo "Login successful"
else
	echo "Login failed. Reason:"
	cat ${outputfile}
	cat ${tracefile}

	exit -1
fi
### If password not set, extract 'SID' and put it into the cookiejarfile.
if grep -q -e KDGchangePW ${outputfile};
then
	echo "Password not set - using SID"
	#KDGchangePW;SID=599652352
	regex=';SID=([0-9]*)'
	reply=$(cat ${outputfile})
	[[ "$reply" =~ $regex ]]
	echo "Found:"
	echo "${BASH_REMATCH[1]}"
	
fi
	

if $DEBUG #toggle Telefony>Configuration>ShowDateAndTimeForCallerID
then
	#Result can be observed on http://${routerip}/voip_page/CbnMtaConfiguration.html
	echo "Toggling Telefony>Configuration>ShowDateAndTimeForCallerID"
	
	sleep 1s
	curl  -i --silent -H "${USERAGENT}" --trace ${tracefile} --output ${outputfile} --cookie ${cookiejarfile} --cookie-jar ${cookiejarfile} "http://${HOST}/xml/getter.xml" -d "token=${SESSIONTOKEN}&fun=508" -w "\n\n%{http_code}\n"   -H 'Accept: application/xml, text/xml, */*; q=0.01' -H 'X-Requested-With: XMLHttpRequest' 
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
	curl --silent -i -H "${USERAGENT}" --trace ${tracefile} --output ${outputfile} --cookie ${cookiejarfile} --cookie-jar ${cookiejarfile} "http://${HOST}/xml/setter.xml" -d "token=${SESSIONTOKEN}&fun=509&Enable=${toggleenable}" -w "\n\n%{http_code}\n"   -H 'Accept: application/xml, text/xml, */*; q=0.01' -H 'X-Requested-With: XMLHttpRequest'  
	retrieveToken
	
	#Logout
	curl --silent -i -H "${USERAGENT}" --trace ${tracefile} --output ${outputfile} --cookie ${cookiejarfile} --cookie-jar ${cookiejarfile} "http://${HOST}/xml/setter.xml" -d "token=${SESSIONTOKEN}&fun=16" -w "\n\n%{http_code}\n"   -H 'Accept: application/xml, text/xml, */*; q=0.01' -H 'X-Requested-With: XMLHttpRequest'  
	retrieveToken
fi

if  ! $DEBUG #Reboot
then
	echo "Sending Reboot Command"
	sleep 1s
	curl --silent -i -H "${USERAGENT}" --trace ${tracefile} --cookie ${cookiejarfile} --cookie-jar ${cookiejarfile} "http://${HOST}/xml/setter.xml" -d "token=${SESSIONTOKEN}&fun=8" 
	retrieveToken
fi

rm -f ${cookiejarfile}
rm -f ${outputfile}
rm -f ${tracefile}
