FROM ubuntu:noble
ARG DEBIAN_FRONTEND=noninteractive


#COPY ./index.html /usr/local/apache2/htdocs/
#COPY data.json /usr/local/apache2/htdocs/data

# This is to mimic the legacy XCONF service api availability for the test cases
# In a new environment bring up, would have hosted the service without references to loguploader
# However to support the legacy backend service, the XCONF response even today has references to loguploader settings
# RUN mkdir -p /usr/local/apache2/htdocs/loguploader
# COPY xconf-dcm-response.json /usr/local/apache2/htdocs/loguploader/getT2DCMSettings

RUN apt-get update && apt-get install -y vim curl wget nodejs npm openssl

RUN mkdir -p /opt
RUN cd /opt
RUN openssl genrsa -out key.pem 2048
RUN openssl req -new -days 730 -key key.pem -out csr.pem -subj "/C=US/ST=CA/L=San Francisco/O=Platform Security/OU=Platform Security/CN=mockxconf" 
RUN openssl x509 -req -in csr.pem -signkey key.pem -out cert.pem

# Create a directory to store the certificates
RUN mkdir -p /etc/xconf/certs
RUN mv key.pem /etc/xconf/certs/mock-xconf-server-key.pem
RUN mv cert.pem /etc/xconf/certs/mock-xconf-server-cert.pem
RUN rm -rf /opt/*

# TODO: Upgrade to mtls support depending on the offerings from wrappers for SSA


RUN mkdir -p /mnt/L2_CONTAINER_SHARED_VOLUME

# Reduce image size 
RUN apt-get clean && rm -rf /var/lib/apt/lists/*

# Install the apps and dependencies
RUN mkdir -p /etc/xconf/
COPY xconf-dcm-response.json /etc/xconf/xconf-dcm-response.json
COPY xconf-dcm-response1.json /etc/xconf/xconf-dcm-response1.json
COPY xconf-cdl-response.json /etc/xconf/xconf-cdl-response.json
COPY xconf-cdl-invalid-response.json /etc/xconf/xconf-cdl-invalid-response.json
COPY xconf-cdl-invalidpci-response.json /etc/xconf/xconf-cdl-invalidpci-response.json
COPY xconf-cdl-delaydwnl-response.json /etc/xconf/xconf-cdl-delaydwnl-response.json
COPY xconf-cdl-reboottrue-response.json /etc/xconf/xconf-cdl-reboottrue-response.json
COPY xconf-peripheralcdl-response.json /etc/xconf/xconf-peripheralcdl-response.json
COPY xconf-peripheralcdl-404response.json /etc/xconf/xconf-peripheralcdl-404response.json
COPY xconf-rfc-response.json /etc/xconf/xconf-rfc-response.json
COPY firmware_test.bin /etc/xconf/firmware_test.bin
COPY firmware_test.bin /etc/xconf/ABCD_firmware_test.bin
COPY firmware_test.bin /etc/xconf/ABCD_PDRI_firmware_test.bin
COPY firmware_test.bin /etc/xconf/AB11-20_firmware_5103.3.4.tgz

RUN mkdir -p /usr/local/bin
COPY ./entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

COPY data-lake-mock.js /usr/local/bin/data-lake-mock.js
RUN chmod +x /usr/local/bin/data-lake-mock.js

COPY getT2DCMSettings.js /usr/local/bin/getT2DCMSettings.js

COPY getXconfData.js /usr/local/bin/getXconfData.js
RUN chmod +x /usr/local/bin/getXconfData.js

COPY rfcData.js /usr/local/bin/rfcData.js
RUN chmod +x /usr/local/bin/rfcData.js

COPY rrdFileupload.js /usr/local/bin/rrdFileupload.js
RUN chmod +x /usr/local/bin/rrdFileupload.js

CMD ["/usr/local/bin/entrypoint.sh"]

EXPOSE 50050
EXPOSE 50051
EXPOSE 50052
EXPOSE 50053
EXPOSE 50054

