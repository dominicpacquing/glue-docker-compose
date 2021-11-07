FROM maven:3.8.3-openjdk-8

ARG PYTHON_VERSION=3.7.10
ARG SCALA_VERSION=2.11
ARG SPARK_VERSION=2.4.3
ARG GLUE_VERSION=2.0
ARG HADOOP_VERSION=2.8
ARG MINICONDA_VERSION=4.7.12
ARG AWS_DEFAULT_REGION=ap-southeast-2

ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8

USER root
ENV HOME /root

ENV CONDA_HOME $HOME/install/conda
ENV SPARK_HOME $HOME/install/spark-${SPARK_VERSION}-bin-spark-${SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}
ENV GLUE_HOME $HOME/install/aws-glue-libs
ENV PATH $SPARK_HOME/bin:$CONDA_HOME/bin:$PATH:$ADDITIONAL_PATH
ENV AWS_DEFAULT_REGION $AWS_DEFAULT_REGION

RUN apt-get update --fix-missing && apt-get install -y \
    build-essential \
    curl \
    git \
    make \
    libssl-dev \
    libffi-dev \
    zlib1g-dev \
    libbz2-dev \
    libreadline-dev \
    libsqlite3-dev \
    zip \
    unzip

# Install aws-cli v2
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
RUN unzip /tmp/awscliv2.zip -d /tmp
RUN bash /tmp/aws/install

# Install PYTHON
RUN curl -sSL https://repo.continuum.io/miniconda/Miniconda3-$MINICONDA_VERSION-Linux-x86_64.sh -o /tmp/miniconda.sh \
    && bash /tmp/miniconda.sh -bfp $CONDA_HOME \
    && rm -rf /tmp/miniconda.sh \
    && conda install -y python=$PYTHON_VERSION \
    && conda update conda \
    && apt-get autoclean \
    && rm -rf /var/lib/apt/lists/* /var/log/dpkg.log \
    && conda clean --all --yes

# Install Glue python packages
# https://docs.aws.amazon.com/glue/latest/dg/aws-glue-programming-python-libraries.html
COPY src/install/requirements.txt .
RUN pip install -r requirements.txt

# Install Glue Spark distribution
RUN mkdir -p $SPARK_HOME
RUN curl "https://aws-glue-etl-artifacts.s3.amazonaws.com/glue-${GLUE_VERSION}/spark-${SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}.tgz" \
    -o /tmp/glue-${GLUE_VERSION}-spark-${SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}.tgz
RUN tar -xf /tmp/glue-${GLUE_VERSION}-spark-${SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}.tgz --strip-components=1 -C $SPARK_HOME
RUN rm /tmp/glue-${GLUE_VERSION}-spark-${SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}.tgz

RUN mkdir -p ${GLUE_HOME}
RUN git clone https://github.com/awslabs/aws-glue-libs $GLUE_HOME && \
    cd $GLUE_HOME && git checkout glue-${GLUE_VERSION}

RUN mvn -f $GLUE_HOME/pom.xml -DoutputDirectory=$GLUE_HOME/jars dependency:copy-dependencies
RUN rm $GLUE_HOME/jars/servlet-api-2.5.jar && \
    rm $GLUE_HOME/jars/jsr305-1.3.9.jar && \
    rm $GLUE_HOME/jars/jersey-*-1.9.jar

COPY src/config/spark/pom.xml $HOME/install/spark-pom.xml
RUN mvn -f $HOME/install/spark-pom.xml \
    -Dscala-version=${SCALA_VERSION} \
    -Dspark-version=$SPARK_VERSION \
    -DoutputDirectory=${SPARK_HOME}/jars \
    dependency:copy-dependencies

COPY src/config/hadoop/core-site.xml $SPARK_HOME/conf/
COPY src/config/spark/spark-env.sh $SPARK_HOME/conf/
COPY src/config/spark/spark-defaults.conf $SPARK_HOME/conf/

COPY src/config/config $HOME/.aws/config

# Add py4j to python path
ENV PYTHONPATH $GLUE_HOME:$SPARK_HOME/python/:$SPARK_HOME/python/lib/py4j-0.10.7-src.zip

RUN rm $GLUE_HOME/jars/netty-*

WORKDIR $HOME

ENTRYPOINT []
CMD ["/bin/sh"]
