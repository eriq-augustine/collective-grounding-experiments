# A good statring point for PSL images.

FROM ubuntu:20.04

# BEGIN LINQS_BASE

USER root

ARG BASEUSER=linqs
ARG PASSWORD=linqs
ARG UID=1000
ARG GID=1000

ENV DOCKER=true

RUN groupadd -f --non-unique --gid ${GID} ${BASEUSER}
RUN useradd --create-home --uid ${UID} --gid ${GID} --password ${PASSWORD} ${BASEUSER}
RUN echo "${BASEUSER}:${PASSWORD}" | chpasswd

WORKDIR /home/${BASEUSER}

RUN mkdir temp

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update --fix-missing

RUN ln -fs /usr/share/zoneinfo/America/Los_Angeles /etc/localtime
RUN apt-get -y install tzdata locales

RUN echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
RUN echo "LANG=en_US.UTF-8" > /etc/locale.conf
RUN locale-gen

RUN apt-get install -y sudo
RUN usermod -a -G sudo ${BASEUSER}

RUN apt-get install -y curl git maven time tmux tree vim wget
RUN apt-get install -y python3-pip python3-setuptools
RUN pip3 install -U pip setuptools

# Cleanup permissions.
RUN chown -R ${UID}:${GID} .

# User-level operations.

# Set default user.
USER ${UID}:${GID}

RUN git clone https://github.com/eriq-augustine/skeletons.git
RUN cp skeletons/_.bashrc .bashrc
RUN cp skeletons/_.vimrc .vimrc
RUN cp skeletons/_.bash_aliases .bash_aliases
RUN cp skeletons/_.bash_profile .bash_profile
RUN cp skeletons/_.gitconfig .gitconfig

# END LINQS_BASE

# BEGIN PSL_BASE

USER root

# Setup Java.

RUN apt-get update
RUN apt-get install -y openjdk-8-jdk postgresql
RUN update-java-alternatives --set java-1.8.0-openjdk-amd64

# Setup postgres.

RUN sed -i '/replication\s\+all/d' /etc/postgresql/12/main/pg_hba.conf
RUN sed -i 's/peer$/trust/' /etc/postgresql/12/main/pg_hba.conf
RUN sed -i 's/md5$/trust/' /etc/postgresql/12/main/pg_hba.conf

# Up the postgres service just long enough to add users and DBs.
# Note that services don't stay up between RUN commands.
RUN service postgresql start && \
    su -c 'createuser -d -e -l -r -s psl' postgres && \
    createuser -U psl -s ${BASEUSER} && \
    createdb -U psl ${BASEUSER} && \
    createdb -U psl psl && \
    createdb -U psl psltest

# Set default user.
USER ${UID}:${GID}

WORKDIR /home/${BASEUSER}

RUN echo "export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64" >> .bashrc
RUN echo "export JDK_HOME=/usr/lib/jvm/java-8-openjdk-amd64" >> .bashrc

# END PSL_BASE

# BEGIN Collective Grounding Experiments

USER root

RUN echo "%sudo ALL=(ALL) NOPASSWD: /home/${BASEUSER}/scripts/clear_cache.sh" >> /etc/sudoers

# END Collective Grounding Experiments

USER ${BASEUSER}

WORKDIR /home/${BASEUSER}
