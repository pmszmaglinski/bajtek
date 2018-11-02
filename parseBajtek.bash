#!/bin/bash

# Load credentials
source .credentials

# Urls
baseUrl='http://stare.e-gry.net'
prefixUrl="${baseUrl}/czasopisma"

# Web authentication
loginUrl="${baseUrl}/login"
cookieName='.cookie'

# Logging
logFile='.output.log'

# Initiate log file
touch $logFile

# Temp dir to stage downloading
tempDir='.tmp'

# Newspapers to download
papers=('bajtek' 'top-secret' 'commodore-amiga')

# String to search the newspapers for
searchString='Szmaglinski'



# Get authorization cookie
curl -c $cookieName -d "login=${urlLogin}&pass=${urlPassword}" $loginUrl


trap cleanup 1 2 3 6

cleanup()
{
  echo "****************************************"
  echo "Caught Signal ... cleaning up ${tempDir}"
  sleep 1
  rm -rf ${tempDir}/*
  echo "Done cleanup ... quitting."
  echo "****************************************"
  exit 1
}


downloadPapers() {
    for j in "${papers[@]}"; do

      # Create dir for paper if doesn't exists yet and temp dir
      downloadDir="files/${j}"
      [[ -d ${downloadDir} ]] || mkdir -p ${downloadDir}
      [[ -d ${tempDir} ]] || mkdir -p ${tempDir}

      # Set url to grab the download links
      linksUrl="${prefixUrl}/${j}"

      # Get links to newspapers
      for i in $(curl -s $linksUrl | grep czasopisma/download | grep -Po 'href="/\K[^"]*')
        do  
            # Set url for download
            downloadUrl="${baseUrl}/${i}"

            # Get download cookie
            curl -s -b $cookieName -c $cookieName $downloadUrl > /dev/null

            # Get file name to save
            fileName=$(curl -s -b $cookieName $downloadUrl -I |  grep 'Location' | sed 's/^.*\///' | tr -d '\r')
            #baseFileName=${fileName%.djvu}
           
            # Move to next if file already exists
            [[ -f "${downloadDir}/${fileName}" ]] && echo "Skipping already existing file: ${downloadDir}/${fileName}" | tee -a $logFile && continue

            # Download file to temporary dir
            echo "Downloading a file: ${fileName}" | tee -a $logFile
            curl -s -L -b $cookieName $downloadUrl --retry 5 --output "${tempDir}/${fileName}" >> $logFile 2>&1
            [[ $? -ne 0 ]] && echo "Error downloading file: ${tempDir}/${fileName}" | tee -a $logFile && exit 1

            # Move file to target location
            echo "Moving file to ${downloadDir}/${fileName}" | tee -a $logFile
            mv "${tempDir}/${fileName}" "${downloadDir}/${fileName}"
            echo -e "\n" | tee -a $logFile
      done
    done

    # Cleanup stuff
    [[ -f ${cookieName} ]] && rm -rf ${cookieName}
    [[ -d ${tempDir} ]] && rm -rf ${tempDir}
}


djvuToPdf() {

 echo -e "\n***************************************" | tee -a $logFile
 echo -e "**** Converting djvu files to pdf *****" | tee -a $logFile
 echo -e "***************************************\n" | tee -a $logFile

 # Create temp dir if not exists
 [[ -d ${tempDir} ]] || mkdir -p ${tempDir}
 
 # Get number of files to convert
 numOfFiles=$(find files/ -iname '*.djvu'| wc -l)
 [[ $numOfFiles -eq 0 ]] && echo -e "No djvu files found in file/\n" | tee -a $logFile && exit 0


 # Convert the djvu file to pdf and ocr(ddjvu from djvulibre-bin pakcage)
 for i in $(find files/ -iname '*.djvu');
  do
    echo -e "${numOfFiles} left to convert" | tee -a $logFile
    echo "Proceeding file ${i##*/}" | tee -a $logFile
    echo "djvu file size $(du -h ${i} | cut -f1)" | tee -a $logFile

    pdfFile=${i%.djvu}.pdf

    # If page is corrupted skip it (dont give non-zero output)
    ddjvu -format=pdf $i "${tempDir}/${pdfFile##*/}" -skip 2>&1 | tee -a $logFile
    [[ $? -ne 0 ]] && echo "Convert to pdf failed for: ${i}" | tee -a $logFile && exit 1
    mv "${tempDir}/${pdfFile##*/}" "${pdfFile}"
    rm -rf $i
    echo -e "pdf file size $(du -h ${pdfFile} | cut -f1)\n" | tee -a $logFile

    numOfFiles=$(($numOfFiles-1))
  done
}

addOcr() {
 # Add ocr layer (ocrmypdf package) to make pdf readable to pdfgrep
 for i in $(find files/ -iname '*.pdf');
  do
    # Add ocr layer
    echo "Adding ocr layer for file: ${i}"
    ocrFile=${i%.pdf}_ocr.pdf
    ocrmypdf $i ${ocrFile} >> $logFile 2>&1
    [[ $? -ne 0 ]] && echo "Adding ocr layer failed for: $i" && exit 1
    rm -rf $i
  done
}

searchForString() {
 # Search for a string
 echo "Searching for a string ${searchString}"
 pdfgrep -n $searchString "files/${baseFileName}_ocr.pdf"
}

#downloadPapers
djvuToPdf
#addOcr
