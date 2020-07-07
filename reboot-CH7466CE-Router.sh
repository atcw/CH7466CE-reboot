#!/bin/bash

# Reboot your Cable Gateway / Router
# For 	 - Firmware-Version  4.50.20.3 (above and earlier)
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
	SESSIONTOKEN=$(awk '/sessionToken/ { print $7 }' "${cookiejarfile}")
	echo "SESSIONTOKEN: " "${SESSIONTOKEN}"
}

function getRequest # $1:url
{
	sleep 1s
	HTTPSTATUS=$( 
	curl  -i `# show response headers` \
		-L `# follow location` \
		-H "${USERAGENT}" \
		--silent `# no progress bar` \
		--trace-ascii "${tracefile}" \
		--output "${outputfile}" `#no visible body output` \
		--cookie "${cookiejarfile}" `#read` \
		--cookie-jar  "${cookiejarfile}" `#write` \
		--location `#follow` \
		--write-out "%{http_code}" `#Status-Code` \
		"http://${HOST}/${1}" 
	)
	retrieveToken
}

function postRequest # $1:url, $2:urlencoded-form-data
{
	sleep 1s
	HTTPSTATUS=$( 
	curl  -i `# show response headers` \
		-L `# follow location` \
		-H "${USERAGENT}" \
		-H 'Accept: application/xml, text/xml, */*; q=0.01' \
		-H 'X-Requested-With: XMLHttpRequest' \
		--silent `# no progress bar` \
		--trace-ascii "${tracefile}" \
		--output "${outputfile}" `#no visible body output` \
		--cookie "${cookiejarfile}" `#read` \
		--cookie-jar  "${cookiejarfile}" `#write` \
		--location `#follow` \
		--write-out "%{http_code}" `#Status-Code` \
		"http://${HOST}/$1" \
		-d "token=${SESSIONTOKEN}&${2}"
	)
	retrieveToken
}

#### Get a sessiontoken #####
# Try until sessiontoken is properly generated. Requests are intentionally redundant.
until [ "${SESSIONTOKEN}" != "0" ]
do
	#follow location header #no --cookie ${cookiejarfile} yet.
	getRequest "" # gets root as in "/"
	
	echo Http-Status: "$HTTPSTATUS"
	#cat ${outputfile}
	
	### Login won't work without having requested "fun=3" (some info) before.
	postRequest "xml/getter.xml" "fun=3"
	
	getRequest "common_page/login.html"
	
	if [ "${SESSIONTOKEN}" == "0" ]
		then
			echo waiting 5 sec because the sessiontoken is still bad
			sleep 5s
			#Get a large picture to trigger state change on the router.
			getRequest "images/common_imgs/cbn_logo.png"

	fi
	echo "About to test token"
done
echo "Token ok."

#### Login #####
postRequest "xml/setter.xml" "fun=15&Username=${LOGINUSER}&Password=${LOGINPASSWORD}"

echo Http-Status: "$HTTPSTATUS"

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
	exit 1
fi
	
if grep -q -e successful -e KDGchangePW "${outputfile}";
then
	echo "Login successful"
else
	echo "Login failed. Reason:"
	cat "${outputfile}"
	exit 1
fi

### If password was not yet changed from default on router, 'SID' needs to be extracted and put into the cookiejarfile.
if grep -q -e KDGchangePW "${outputfile}";
then
	echo "Password not changed from default."
	regex=';SID=([0-9]*)' #KDGchangePW;SID=599652352
	reply=$(cat "${outputfile}")
	[[ "$reply" =~ $regex ]]
	echo "Found SID: ${BASH_REMATCH[1]}"
	#append to Netscape-style cookiejarfile
	echo -e "${HOST}\tFALSE\t/\tFALSE\t0\tSID\t${BASH_REMATCH[1]}">>"${cookiejarfile}" #https://github.com/koalaman/shellcheck/wiki/SC2028 later
fi
	

### we are logged in ###

### time for some actual work ###

if $DEBUG #test toggling values
then
	#Result can be observed on http://${routerip}/voip_page/CbnMtaConfiguration.html
	# 1 is off, 0 is on. Sic!
	echo "Toggling Telefony>Configuration>ShowDateAndTimeForCallerID"
	

	postRequest "xml/getter.xml" "fun=508"
	reply=$(cat "${outputfile}")

	regex='<DateAndTimeEnable>([0-9])</DateAndTimeEnable>'
	[[ "$reply" =~ $regex ]]
	echo "Found DateAndTimeEnable: ${BASH_REMATCH[1]}"
	toggleenable=${BASH_REMATCH[1]}
	#invert to toggle
	[ "$toggleenable" = "0" ] && toggleenable="1" || toggleenable="0";
	
	postRequest "xml/setter.xml" "fun=509&Enable=${toggleenable}" 
	
	#Logout
	postRequest "xml/setter.xml" "fun=16"
	
fi

if  ! $DEBUG #Reboot
then
	postRequest "xml/setter.xml" "fun=8"
fi

### clean up ###

rm -f "${cookiejarfile}"
rm -f "${outputfile}"
rm -f "${tracefile}"
