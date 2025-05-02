###################
# STAGE 1: builder
###################

FROM node:22-bullseye as builder

ARG MB_EDITION=oss
ARG VERSION=v0.49.2

ENV MB_EDITION=${MB_EDITION}
ENV VERSION=${VERSION}

WORKDIR /home/node

# Install Java 21, Clojure, Git
RUN apt-get update && apt-get upgrade -y && apt-get install wget apt-transport-https gpg curl git -y \
    && wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public | gpg --dearmor | tee /etc/apt/trusted.gpg.d/adoptium.gpg > /dev/null \
    && echo "deb https://packages.adoptium.net/artifactory/deb $(awk -F= '/^VERSION_CODENAME/{print$2}' /etc/os-release) main" | tee /etc/apt/sources.list.d/adoptium.list \
    && apt-get update \
    && apt install temurin-21-jdk -y \
    && curl -O https://download.clojure.org/install/linux-install-1.12.0.1488.sh \
    && chmod +x linux-install-1.12.0.1488.sh \
    && ./linux-install-1.12.0.1488.sh

# Copy all source code
COPY . .

# Fix for Git safe directory warning in CI
RUN git config --global --add safe.directory /home/node

# Install frontend dependencies
RUN yarn --frozen-lockfile

# Build Metabase
RUN INTERACTIVE=false CI=true MB_EDITION=$MB_EDITION bin/build.sh :version $VERSION

###################
# STAGE 2: runner
###################

FROM eclipse-temurin:21-jre-alpine as runner

ENV FC_LANG en-US
ENV LC_CTYPE en_US.UTF-8

# Install fonts and certs for DB support
RUN apk add -U bash fontconfig curl font-noto font-noto-arabic font-noto-hebrew font-noto-cjk java-cacerts && \
    apk upgrade && \
    rm -rf /var/cache/apk/* && \
    mkdir -p /app/certs && \
    curl https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem -o /app/certs/rds-combined-ca-bundle.pem  && \
    /opt/java/openjdk/bin/keytool -noprompt -import -trustcacerts -alias aws-rds -file /app/certs/rds-combined-ca-bundle.pem -keystore /etc/ssl/certs/java/cacerts -keypass changeit -storepass changeit && \
    curl https://cacerts.digicert.com/DigiCertGlobalRootG2.crt.pem -o /app/certs/DigiCertGlobalRootG2.crt.pem  && \
    /opt/java/openjdk/bin/keytool -noprompt -import -trustcacerts -alias azure-cert -file /app/certs/DigiCertGlobalRootG2.crt.pem -keystore /etc/ssl/certs/java/cacerts -keypass changeit -storepass changeit && \
    mkdir -p /plugins && chmod a+rwx /plugins

# Copy built artifacts from builder
COPY --from=builder /home/node/target/uberjar/metabase.jar /app/
COPY bin/docker/run_metabase.sh /app/

# Expose default port
EXPOSE 3000

# Start Metabase
ENTRYPOINT ["/app/run_metabase.sh"]
