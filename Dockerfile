# This file is based on Google TensorFlow Serving Dockerfile.devel file with
# Modifications needed to build the project for CentOS 7.
# Original file is licenced under Apache Licence, Version 2.0:
# https://github.com/tensorflow/serving/blob/master/tensorflow_serving/tools/docker/Dockerfile.devel

FROM centos:7 as build-image

# Set locale
ENV LANG en_US.UTF-8
ARG TF_SERVING_VERSION_GIT_BRANCH=master
# Release Tag 2.8
ARG TF_SERVING_VERSION_GIT_COMMIT=9400ef162ea4b9f6d6dcc40c55b7d4e03d733ef0

# Original LABEL maintainer=gvasudevan@google.com
LABEL tensorflow_serving_github_branchtag=${TF_SERVING_VERSION_GIT_BRANCH}
LABEL tensorflow_serving_github_commit=${TF_SERVING_VERSION_GIT_COMMIT}

# Enable SCL CentOS 7 repo and install build packages
RUN yum install -y centos-release-scl && yum update -y && yum install -y \
        which \
        devtoolset-9-gcc \
        devtoolset-9-gcc-c++ \
        devtoolset-9-libstdc++-devel \
        devtoolset-9-make \
        patch \
        automake \
        ca-certificates \
        curl \
        git \
        libtool \
        mlocate \
        java-1.8.0-openjdk-devel \
        swig \
        unzip \
        wget \
        zip \
        zlib1g-dev \
        python3-distutils&& \
    yum clean all && \
    rm -rf /var/lib/apt/lists/*

# Install python 3.7
RUN yum update -y && \
    yum install -y wget gcc make zlib-devel bzip2-devel openssl-devel ncurses-devel sqlite-devel readline-devel tk-devel libffi-devel  && \
    wget -c https://www.python.org/ftp/python/3.7.12/Python-3.7.12.tgz && \
    tar -zxf Python-3.7.12.tgz && \
    cd Python-3.7.12 && \
    source /opt/rh/devtoolset-9/enable && \
    ./configure prefix=/opt/python37 && \
    make -j && make install && \
    cd .. && \
    rm -rf Python-3.7.12 Python-3.7.12.tgz && \
    update-alternatives --install /usr/bin/python3 python3 /opt/python37/bin/python3.7 0

# Install pip
RUN curl -fSsL -O https://bootstrap.pypa.io/get-pip.py && \
    python3 get-pip.py && \
    rm get-pip.py

# Install Python dependencies
RUN python3 -m pip --no-cache-dir install \
    future>=0.17.1 \
    grpcio \
    h5py \
    keras_applications>=1.0.8 \
    keras_preprocessing>=1.1.0 \
    mock \
    numpy \
    portpicker \
    requests \
    --ignore-installed setuptools \
    --ignore-installed six>=1.12.0

# Set up Bazel
ENV BAZEL_VERSION 3.7.2
WORKDIR /
RUN mkdir /bazel && \
    cd /bazel && \
    curl -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/57.0.2987.133 Safari/537.36" -fSsL -O https://github.com/bazelbuild/bazel/releases/download/$BAZEL_VERSION/bazel-$BAZEL_VERSION-installer-linux-x86_64.sh && \
    curl -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/57.0.2987.133 Safari/537.36" -fSsL -o /bazel/LICENSE.txt https://raw.githubusercontent.com/bazelbuild/bazel/master/LICENSE && \
    chmod +x bazel-*.sh && \
    ./bazel-$BAZEL_VERSION-installer-linux-x86_64.sh && \
    cd / && \
    rm -f /bazel/bazel-$BAZEL_VERSION-installer-linux-x86_64.sh

# Download TF Serving sources (optionally at specific commit).
WORKDIR /tensorflow-serving
RUN curl -sSL --retry 5 https://github.com/tensorflow/serving/tarball/${TF_SERVING_VERSION_GIT_COMMIT} | tar --strip-components=1 -xzf -

# Build, and install TensorFlow Serving
ARG TF_SERVING_BUILD_OPTIONS="--config=release --jobs 16"
RUN echo "Building with build options: ${TF_SERVING_BUILD_OPTIONS}"
# Add Support for AVX (Support from SandyBridge)
ARG TF_SERVING_BAZEL_OPTIONS="--copt=-msse4.1 --copt=-msse4.2 --copt=-mavx"
RUN echo "Building with Bazel options: ${TF_SERVING_BAZEL_OPTIONS}"

# Added BAZEL_LINKLIBS=-l%:libstdc++.a due to the issue explained here: https://github.com/tensorflow/serving/issues/1563
RUN source /opt/rh/devtoolset-9/enable && \
    BAZEL_LINKLIBS=-l%:libstdc++.a bazel build --color=yes --curses=yes \
    ${TF_SERVING_BAZEL_OPTIONS} \
    --verbose_failures \
    --output_filter=DONT_MATCH_ANYTHING \
    ${TF_SERVING_BUILD_OPTIONS} \
    tensorflow_serving/model_servers:tensorflow_model_server && \
    cp bazel-bin/tensorflow_serving/model_servers/tensorflow_model_server \
    /usr/local/bin/

# Build and install TensorFlow Serving API
RUN source /opt/rh/devtoolset-9/enable && \
    BAZEL_LINKLIBS=-l%:libstdc++.a bazel build --color=yes --curses=yes \
    ${TF_SERVING_BAZEL_OPTIONS} \
    --verbose_failures \
    --output_filter=DONT_MATCH_ANYTHING \
    ${TF_SERVING_BUILD_OPTIONS} \
    tensorflow_serving/tools/pip_package:build_pip_package && \
    bazel-bin/tensorflow_serving/tools/pip_package/build_pip_package \
    /tmp/pip

FROM centos:7
COPY --from=build-image /usr/local/bin/tensorflow_model_server /usr/local/bin/
RUN mkdir -p /opt/whl
COPY --from=build-image /tmp/pip/tensorflow_serving_api-*.whl /opt/whl
