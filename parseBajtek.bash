#!/bin/bash

# Load credentials
source .credentials

# Urls
baseUrl='http://stare.e-gry.net'
prefixUrl="${baseUrl}/czasopisma"

papers=('bajtek' 'top-secret' 'commodore-amiga')


# Authentication
loginUrl="${baseUrl}/login"
cookieName='.cookie'

# Logging
logFile='.output.log'

searchString='jazdy'

# Initiate log file
touch $logFile

# Get authorization cookie
curl -c $cookieName -d "login=${urlLogin}&pass=${urlPassword}" $loginUrl

for j in "${papers[@]}"; do

  # Create dir for paper if doesn't exists yet
  downloadDir="files/${j}"
  [[ -d ${downloadDir} ]] || mkdir -p ${downloadDir}

  # Set url to grab the download links
  linksUrl="${prefixUrl}/${j}"

  for i in $(curl -s $linksUrl | grep czasopisma/download | grep -Po 'href="/\K[^"]*')
    do 
        downloadUrl="${baseUrl}/${i}"
        echo "Parsing link: ${downloadUrl}"

        # Get download cookie
        curl -s -b $cookieName -c $cookieName $downloadUrl > /dev/null

        # Get file name to save
        fileName=$(curl -s -b $cookieName $downloadUrl -I |  grep 'Location' | sed 's/^.*\///' | tr -d '\r')
        baseFileName=${fileName%.djvu}

        # Download file
        echo "Pobieram plik ${fileName} z linku ${downloadUrl} do katalogu ${downloadDir}"
        curl -s -L -b $cookieName $downloadUrl --output ${downloadDir}/${fileName} >> $logFile 2>&1

        break
  done
done

convertToPdf() {
 # Convert the djvu file to pdf (ddjvu from djvulibre-bin pakcage)
 echo "Converting to pdf format..."
 ddjvu -format=pdf "files/${fileName}" "files/${baseFileName}.pdf"
 rm -f "files/${fileName}"
}

convertToOcr() {
 # Add ocr layer (ocrmypdf package) to make pdf readable to pdfgrep
 echo "Converting to ocr layer..."
 ocrmypdf files/${baseFileName}.pdf files/${baseFileName}_ocr.pdf >> $logFile 2>&1
}

searchForString() {
 # Search for a string
 echo "Searching for a string ${searchString}"
 pdfgrep -n $searchString "files/${baseFileName}_ocr.pdf"
}
