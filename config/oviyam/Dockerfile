FROM tomcat:9-jre11

LABEL maintainer="PACS System"
LABEL version="2.8.2"
LABEL description="Oviyam DICOM Web Viewer"

ENV OVIYAM_VERSION=2.8.2 \
    CATALINA_OPTS="-Xms512m -Xmx2048m -XX:+UseG1GC" \
    JAVA_OPTS="-Djava.awt.headless=true -Djava.security.egd=file:/dev/./urandom"

RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    unzip \
    curl \
    netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /usr/local/tomcat/webapps/oviyam

RUN mkdir -p /usr/local/tomcat/webapps/oviyam/WEB-INF && \
    mkdir -p /usr/local/tomcat/webapps/oviyam/META-INF

RUN echo '<?xml version="1.0" encoding="UTF-8"?>\n\
<web-app xmlns="http://xmlns.jcp.org/xml/ns/javaee"\n\
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"\n\
         xsi:schemaLocation="http://xmlns.jcp.org/xml/ns/javaee\n\
         http://xmlns.jcp.org/xml/ns/javaee/web-app_4_0.xsd"\n\
         version="4.0">\n\
    <display-name>Oviyam DICOM Viewer</display-name>\n\
    <welcome-file-list>\n\
        <welcome-file>index.html</welcome-file>\n\
        <welcome-file>index.jsp</welcome-file>\n\
    </welcome-file-list>\n\
</web-app>' > /usr/local/tomcat/webapps/oviyam/WEB-INF/web.xml

RUN echo '<!DOCTYPE html>\n\
<html>\n\
<head>\n\
    <title>Oviyam DICOM Viewer</title>\n\
    <meta charset="UTF-8">\n\
</head>\n\
<body>\n\
    <h1>Oviyam DICOM Viewer</h1>\n\
    <p>Oviyam 2.8.2 - Waiting for configuration</p>\n\
    <p>Please provide oviyam.war file to complete installation</p>\n\
</body>\n\
</html>' > /usr/local/tomcat/webapps/oviyam/index.html

RUN sed -i 's/port="8080"/port="8080" maxHttpHeaderSize="65536" maxPostSize="4194304" URIEncoding="UTF-8"/g' \
    /usr/local/tomcat/conf/server.xml

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:8080/oviyam/ || exit 1

CMD ["catalina.sh", "run"]