FROM ubuntu:latest
RUN apt-get update && apt-get install -y \
    alien \
    unzip \
    wget \
    curl \
    python-setuptools \
    python2.7 \
    python-pip \
    jq \
    ansible \
    vim \
    keychain \
    bash \
    sudo \
    git-core \
    --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

RUN pip install \
    botocore \
    boto3 \
    awsretry \
    awscli

RUN chsh -s /bin/bash

RUN wget --no-check-certificate https://releases.hashicorp.com/terraform/0.12.24/terraform_0.12.24_linux_amd64.zip \
    && unzip terraform_0.12.24_linux_amd64.zip \
    && mv terraform /usr/local/bin/

RUN export VER="1.4.1" \
    && wget https://releases.hashicorp.com/packer/${VER}/packer_${VER}_linux_amd64.zip \
    && unzip packer_${VER}_linux_amd64.zip \
    && mv packer /usr/local/bin

RUN pip install awscli --upgrade

COPY credentials /root/.aws/credentials.tpl
