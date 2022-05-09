FROM maven:3.8.1 as build
ENV MAVEN_OPTS="-Dmaven.wagon.http.ssl.insecure=true -Dmaven.wagon.http.ssl.allowall=true -Dmaven.wagon.http.ssl.ignore.validity.dates=true"
ADD  . .

RUN mvn  clean package

FROM openjdk:11
ENV MICROSERVICE_NAME=java-ref-app
RUN mkdir -p /app/logs /app/config && chmod -R a+rw  /app
WORKDIR /app
ARG JAR_FILE=target/*.jar
COPY --from=build  ${JAR_FILE} java-ref-app.jar

ENTRYPOINT ["java","-Dspring.profiles.active=none","-jar","/app/java-ref-app.jar"]
