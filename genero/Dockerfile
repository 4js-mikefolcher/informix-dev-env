#*****************************************************************************#
## Base Install Image
ARG BASE_IMAGE=ibmcom/informix-developer-sandbox:latest
FROM ${BASE_IMAGE}

#*****************************************************************************#
## Argument (Variable) + Environment Var Setup

ARG USER=genero
ARG GROUP=fourjs
ARG UID=500
ARG GID=2000
ARG FGLGASCONFIGURATION
  # Optional arg to be passed to the fastcgidispatch command as a -f flag.

ARG GST_PCK="fjs-gstsrv-4.01.01-build202211071225-l64xl217.run"

ARG PUBLICKEY="mykey.pub"
ARG FGLLICNUM="TAB#ABCD0123"

ARG GENERO_PASSWORD="Pass123"

ENV DEBIAN_FRONTEND=noninteractive
  # Used to skip prompt questions (a bit like -y with yum).
  # See https://www.cyberciti.biz/faq/explain-debian_frontend-apt-get-variable-for-ubuntu-debian/
ENV HOME="/home/${USER}"
ENV FJS_DIR="/opt/${GROUP}"
ENV USER=${USER}
ENV FGLGASCONFIGURATION=${FGLGASCONFIGURATION}
ENV EXPOSE_HTTP_PORT=80
ENV EXPOSE_SSH_PORT=22
ENV EXPOSE_HTTP_DISPATCH_PORT=6336

ENV GSTDIR="${FJS_DIR}/gst"
ENV GASDIR="${FJS_DIR}/gas"
ENV FGLDIR="${FJS_DIR}/fgl"

# Ensure we are running as root
USER root
#*****************************************************************************#
## Download Prerequisite Packages

# Grab packages
RUN apt-get -o "Acquire::https::Verify-Peer=false" update \
  && apt-get -o "Acquire::https::Verify-Peer=false" install \
  -y --no-install-recommends --no-install-suggests \
  # Leftover packages from the original Dockerfile in case needed in the future.
  # bzip2 \
  # binutils \
  locales \
  # Required to install Genero
  file \
  libncursesw5 \
  curl \
  vim \
  net-tools \
  ca-certificates \
  openssh-server \
  apache2 \
  libapache2-mod-fcgid \
  default-jre-headless \
  # Clean package lists
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* \
  && rm -rf /var/log/apt/history.log /var/log/apt/term.log /var/log/dpkg.log

#*****************************************************************************#
## Create User, Group and Home Directory

# Create User and Group
RUN set -eufx \
  && groupadd -g "${GID}" "${GROUP}" \
  && useradd -d "${HOME}" -u "${UID}" -g "${GID}" -M -N -r -s /bin/bash "${USER}" \
  && mkdir -p "${HOME}" \
  && chown "${USER}:${GROUP}" "${HOME}"

RUN usermod -a -G "${GROUP}" informix

#*****************************************************************************#
RUN  mkdir -p /opt/ibm \
 &&  mkdir -p /opt/ibm/informix \
 &&  mkdir -p /opt/ibm/scripts \
 &&  mkdir -p /opt/ibm/data \
 &&  mkdir -p /opt/ibm/localdata

COPY files/ifxenv.sh /opt/ibm/ifxenv.sh
RUN chown -R informix:fourjs /opt/ibm && chmod -R g+rwx /opt/ibm

# Create Target Directory
RUN mkdir -p "${FJS_DIR}"
RUN chown "${USER}:${GROUP}" "${FJS_DIR}"

#*****************************************************************************#
## Install Informix CSDK Components
USER informix
RUN /home/informix/odbc/installclientsdk -i silent -DLICENSE_ACCEPTED=TRUE -DUSER_INSTALL_DIR=/opt/ibm
RUN chmod -R g+rwx /opt/ibm
COPY files/sqlhosts /opt/ibm/etc/sqlhosts
RUN cat /opt/ibm/etc/sqlhosts

#*****************************************************************************#
## Install Genero Components

# Ensure we are running as $USER
USER ${USER}

# Copy Install Packages
COPY files/${GST_PCK} "/tmp/${GST_PCK}"

# Ensure we are running as root
USER root

RUN chown "${USER}:${GROUP}" "/tmp/${GST_PCK}"
RUN chmod +x "/tmp/${GST_PCK}"

#Create shared directory
RUN mkdir -m 755 /shared && chown "${USER}:${GROUP}" /shared

# Ensure we are running as $USER
USER ${USER}

# Run Install Packages
RUN "/tmp/${GST_PCK}" --accept --install --quiet --target "${GSTDIR}" \
  && rm -f "/tmp/${GST_PCK}" 

RUN  ln -s "${GSTDIR}/gas" "${GASDIR}" \
  && ln -s "${GSTDIR}/fgl" "${FGLDIR}"

# Enable Genero Demos
RUN sed -i -e "s#NOBODY#ALL#g" "${GASDIR}/etc/as.xcf"

# Setup symbolic link to /shared
RUN ln -s "/shared" "${HOME}/shared"

# Setup genero user environment
COPY files/bash_profile "${HOME}/.bash_profile"
RUN mkdir -m 700 "${HOME}/.ssh"
COPY files/${PUBLICKEY} "${HOME}/.ssh/${PUBLICKEY}"
RUN cat "${HOME}/.ssh/${PUBLICKEY}" >> "${HOME}/.ssh/authorized_keys"
COPY files/netrc "${HOME}/.netrc"

# Ensure we are running as root
USER root

# Change permissions on files
RUN chown -R "${USER}:${GROUP}" "${HOME}"
RUN chmod 644 "${HOME}/.bash_profile"
RUN chmod 600 "${HOME}/.ssh/authorized_keys" "${HOME}/.ssh/${PUBLICKEY}"
RUN chmod 600 "${HOME}/.netrc"

#*****************************************************************************#
## Copy over custom configs for Apache and Genero
COPY files/apache-auth "${GASDIR}/apache-auth"
COPY files/fgllicense "${FGLDIR}/etc/fgllicense"
COPY files/entrypoint.sh /entrypoint.sh
COPY files/host_key_algorithms.conf /etc/ssh/sshd_config.d/host_key_algorithms.conf

RUN sed -i -e "s/@@FGLLICENSE@@/${FGLLICNUM}/g" "${FGLDIR}/etc/fgllicense"
RUN echo "genero:${GENERO_PASSWORD}" | chpasswd

#Set locale to en_US
RUN locale-gen en_US.UTF-8
RUN update-locale LANG="en_US.UTF-8" LANGUAGE="en_US"

#*****************************************************************************#
## Apache Configuration Processing
COPY files/gas.conf /etc/apache2/conf-available/gas.conf
RUN cd /etc/apache2/mods-enabled \
  && ln -s ../mods-available/proxy_fcgi.load ./proxy_fcgi.load \
  && ln -s ../mods-available/proxy.load ./proxy.load \
  && ln -s ../mods-available/proxy.conf ./proxy.conf \
  && ln -s ../mods-available/rewrite.load ./rewrite.load
RUN cd /etc/apache2/conf-enabled \
  && ln -s ../conf-available/gas.conf ./gas.conf

#*****************************************************************************#
## Post Install process
RUN chown www-data:www-data "${GASDIR}/apache-auth" \
  && chown "${USER}:${GROUP}" "${FGLDIR}/etc/fgllicense" \
  && chmod a-x "${GASDIR}/apache-auth" "${FGLDIR}/etc/fgllicense" \
  && chmod a+x /entrypoint.sh 

#*****************************************************************************#
## Expose Required Image Ports
EXPOSE ${EXPOSE_HTTP_PORT}
EXPOSE ${EXPOSE_SSH_PORT}
EXPOSE ${EXPOSE_HTTP_DISPATCH_PORT}

#*****************************************************************************#
## Set the Entrypoint

# Set entrypoint to the intialising script
ENTRYPOINT [ "/entrypoint.sh" ]

