FROM centos:7 AS builder
RUN yum -y install epel-release
RUN yum -y install python3-devel java-1.8.0-openjdk-devel gcc gcc-c++ kernel-devel make automake autoconf swig git unzip libtool binutils freetype-devel libpng12-devel zip zlib-devel giflib-devel zeromq3-devel
RUN python3 -m pip install --no-cache-dir  "future>=0.17.1" "grpcio==1.30.0" h5py keras_applications keras_preprocessing mock numpy requests

RUN export PATH="$PATH:$HOME/bin"
ENV BAZEL_VERSION=0.24.1
RUN wget https://github.com/bazelbuild/bazel/releases/download/$BAZEL_VERSION/bazel-$BAZEL_VERSION-installer-linux-x86_64.sh
RUN chmod u+x bazel-$BAZEL_VERSION-installer-linux-x86_64.sh
RUN ./bazel-$BAZEL_VERSION-installer-linux-x86_64.sh --user

ENV TF_SERVING_BUILD_OPTIONS="--config=opt --copt=-mssse3 --copt=-msse4.1 --copt=-msse4.2 --copt=-avx"
RUN git clone https://github.com/tensorflow/serving -b r1.15
WORKDIR /serving
RUN ~/.bazel/bin/bazel build --color=yes --curses=yes \
     --verbose_failures \
     --output_filter=DONT_MATCH_ANYTHING \
     ${TF_SERVING_BUILD_OPTIONS} \
     tensorflow_serving/model_servers:tensorflow_model_server
RUN cp bazel-bin/tensorflow_serving/model_servers/tensorflow_model_server /tensorflow_model_server

FROM centos:7
COPY --from=builder /tensorflow_model_server /usr/local/bin
