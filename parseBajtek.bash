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
touch "${logFile}"

# Temp dir to stage downloading
tempDir='.tmp'

# Newspapers to download
papers=('bajtek' 'top-secret' 'commodore-amiga')



# Get authorization cookie
curl -c "${cookieName}" -d "login=${urlLogin}&pass=${urlPassword}" "${loginUrl}"


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
    [[ -d "${downloadDir}" ]] || mkdir -p "${downloadDir}"
    [[ -d "${tempDir}" ]] || mkdir -p "${tempDir}"

    # Set url to grab the download links
    linksUrl="${prefixUrl}/${j}"

    # Get links to newspapers
    for i in $(curl -s "${linksUrl}" | grep czasopisma/download | grep -Po 'href="/\K[^"]*')
      do  
        # Set url for download
        downloadUrl="${baseUrl}/${i}"

        # Get download cookie
        curl -s -b "${cookieName}" -c "${cookieName}" "${downloadUrl}" > /dev/null

        # Get file name to save
        fileName=$(curl -s -b "${cookieName}" "${downloadUrl}" -I |  grep 'Location' | sed 's/^.*\///' | tr -d '\r')
        #baseFileName=${fileName%.djvu}
        
        # Move to next if file already exists
        [[ -f "${downloadDir}/${fileName}" ]] && \
        echo "Skipping already existing file: ${downloadDir}/${fileName}" | tee -a "${logFile}" && \
        continue

        # Download file to temporary dir (avoid partial download while interrupted)
        echo "Downloading a file: ${fileName}" | tee -a $logFile
        curl -s -L -b "${cookieName}" "${downloadUrl}" --retry 5 --output "${tempDir}/${fileName}" >> "${logFile}" 2>&1
        [[ $? -ne 0 ]] && echo "Error downloading file: ${tempDir}/${fileName}" | tee -a "${logFile}" && exit 1

        # Move file to target location
        echo "Moving file to ${downloadDir}/${fileName}" | tee -a "${logFile}"
        mv "${tempDir}/${fileName}" "${downloadDir}/${fileName}"
        echo -e "\n" | tee -a "${logFile}"
      done
    done

  # Cleanup stuff
  [[ -f "${cookieName}" ]] && rm -rf "${cookieName}"
  [[ -d "${tempDir}" ]] && rm -rf "${tempDir}"
}

printBanner() {
  # $1 - string to display
  local z=$1
  local banerWidth=$((${#z}+6))
  local gap=2
  local stars=$((($banerWidth - ${#z})/2 - $gap))

  printf "\n"
  for i in $(seq $banerWidth); do printf "*";done
  printf "\n"
  for i in $(seq $stars); do printf "%s" "*"; done
  for i in $(seq $gap); do printf "%s" " "; done
  printf "%s" "${z}"
  for i in $(seq $gap); do printf "%s" " "; done
  for i in $(seq $stars); do printf "%s" "*"; done
  printf "\n"
  for i in $(seq $banerWidth); do printf "*";done
  printf "\n\n"
}

getNumberOfFiles() {
  # $1 - dir to search, $2 - filetype to search
  numOfFiles=$(find $1 -iname "*.$2"| wc -l)
  [[ $numOfFiles -eq 0 ]] && \
  echo -e "No $2 files found in $1/\n" | tee -a "${logFile}" && \
  exit 0
}

printHeader() {
  # $1 - path to file
  echo -e "${numOfFiles} left to convert" 
  echo "Proceeding file ${i##*/}" 
  echo -e "File size $(du -h "${i}" | cut -f1)"
}

djvuToPdf() {

  printBanner "Converting djvu files to pdf"  | tee -a "${logFile}"

  # Create temp dir if not exists
  [[ -d ${tempDir} ]] || mkdir -p ${tempDir}
  
  # Get number of files to convert
  getNumberOfFiles 'files' 'djvu'

  # Convert the djvu file to pdf and ocr(ddjvu from djvulibre-bin pakcage)
  for i in $(find files/ -iname '*.djvu');
    do

      printHeader "${i}"  | tee -a "${logFile}"

      pdfFile="${i%.djvu}.pdf"

      # Run convert engine
      # If page is corrupted skip it (dont give non-zero output)
      ddjvu -format=pdf "${i}" "${tempDir}/${pdfFile##*/}" -skip 2>&1 | tee -a "${logFile}"

      [[ $? -ne 0 ]] && echo "Convert to pdf failed for: ${i}" | tee -a "${logFile}" && exit 1

      # Move from temp to destination dir
      mv "${tempDir}/${pdfFile##*/}" "${pdfFile}"
      rm -rf $i

      # Check file size after converting
      echo -e "pdf file size $(du -h "${pdfFile}" | cut -f1)\n" | tee -a "${logFile}"

      numOfFiles=$(($numOfFiles-1))
    done
}

addOcr() {

  printBanner 'Adding OCR Layer' | tee -a "${logFile}"

  # Create temp dir if not exists
  [[ -d "${tempDir}" ]] || mkdir -p "${tempDir}"

  # Get number of files to convert
  getNumberOfFiles 'files' 'pdf'
  
  # Add ocr layer (ocrmypdf package) to make pdf readable to pdfgrep
  for i in $(find files/ -iname '*.pdf');
    do

      # Check if file already has ocr layer by looking for a fonts
      [[ $(pdffonts $i | wc -l) -gt 2 ]] && \
      echo -e "File ${i##*/} already ocr'ed. Skipping...\n" | tee -a "${logFile}" && \
      numOfFiles=$(($numOfFiles-1)) && \
      continue

      printHeader $i  | tee -a "${logFile}"

      # Add ocr layer
      echo -n "Adding ocr layer..."

      # Run ocr engine
      # Require tesseract-ocr-pol package (pol lang pack to tesseract)
      ocrmypdf -l pol $i "${tempDir}/${i##*/}" 2>/dev/null | tee -a "${logFile}"
      [[ $? -ne 0 ]] && echo "Adding ocr layer failed for: $i" && exit 1
      echo " Done !"
      # Move file to target location
      mv -f "${tempDir}/${i##*/}" "${i}"

      # Check file size after converting
      echo -e "File size $(du -h ${i} | cut -f1)\n" | tee -a "${logFile}"

      numOfFiles=$(($numOfFiles-1))
    done
}

searchForString() {
  # $1 - string name to search for
  local searchString=$1
  printBanner 'Searching for a string' | tee -a "${logFile}"

  # Get number of files to convert
  getNumberOfFiles 'files' 'pdf'

  echo "Found ${numOfFiles} files."

  # Search for a string
  echo -e "Search string: ${searchString}\n\n"


  for i in $(find files/ -iname '*.pdf');
    do

    echo -ne "${numOfFiles} left to search."\\r 

    # Run search engine
    pdfgrep -qi "${searchString}" "${i}" && echo "${i}"| tee -a "${logFile}"

    numOfFiles=$(($numOfFiles-1))

    done
}

#downloadPapers
#djvuToPdf
#addOcr
searchForString 'usagi'
