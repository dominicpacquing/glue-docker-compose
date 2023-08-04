FROM openjdk:8-jdk

ARG PYTHON_VERSION=3.7.10
ARG SCALA_VERSION=2.12
ARG SPARK_VERSION=3.1.1
ARG GLUE_VERSION=3.0
ARG HADOOP_VERSION=3.2.1
ARG MINICONDA_VERSION=4.7.12
ARG AWS_DEFAULT_REGION=ap-southeast-2
ARG AWS_REGION=ap-southeast-2
ARG AWS_ACCESS_KEY_ID=foobar
ARG AWS_SECRET_ACCESS_KEY=foobarfoo

USER root
ENV HOME /root

ENV MAVEN_VERSION 3.6.0
ENV MAVEN_HOME /usr/share/maven
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8
ENV MAVEN_CONFIG "$HOME/.m2"
ENV CONDA_HOME $HOME/install/conda
ENV SPARK_HOME $HOME/install/spark-${SPARK_VERSION}-amzn-0-bin-${HADOOP_VERSION}-amzn-3
ENV GLUE_HOME $HOME/install/aws-glue-libs
ENV PATH $SPARK_HOME/bin:$CONDA_HOME/bin:$PATH

ENV AWS_DEFAULT_REGION $AWS_DEFAULT_REGION
ENV AWS_REGION $AWS_REGION
ENV AWS_ACCESS_KEY_ID $AWS_ACCESS_KEY_ID
ENV AWS_SECRET_ACCESS_KEY $AWS_SECRET_ACCESS_KEY


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

# Install maven from AWS
RUN mkdir -p /usr/share/maven /usr/share/maven/ref \
  && curl -fsSL -o /tmp/apache-maven.tar.gz https://aws-glue-etl-artifacts.s3.amazonaws.com/glue-common/apache-maven-${MAVEN_VERSION}-bin.tar.gz \
  && tar -xzf /tmp/apache-maven.tar.gz -C /usr/share/maven --strip-components=1 \
  && rm -f /tmp/apache-maven.tar.gz \
  && ln -s /usr/share/maven/bin/mvn /usr/bin/mvn

COPY src/mvn/settings-docker.xml /usr/share/maven/ref/

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
RUN curl "https://aws-glue-etl-artifacts.s3.amazonaws.com/glue-${GLUE_VERSION}/spark-${SPARK_VERSION}-amzn-0-bin-${HADOOP_VERSION}-amzn-3.tgz" \
    -o /tmp/glue-${GLUE_VERSION}-spark-${SPARK_VERSION}-amzn-0-bin-${HADOOP_VERSION}-amzn-3.tgz
RUN tar -xf /tmp/glue-${GLUE_VERSION}-spark-${SPARK_VERSION}-amzn-0-bin-${HADOOP_VERSION}-amzn-3.tgz --strip-components=1 -C $SPARK_HOME
RUN rm /tmp/glue-${GLUE_VERSION}-spark-${SPARK_VERSION}-amzn-0-bin-${HADOOP_VERSION}-amzn-3.tgz

RUN mkdir -p ${GLUE_HOME}
RUN git clone https://github.com/awslabs/aws-glue-libs $GLUE_HOME && \
    cd $GLUE_HOME && git checkout glue-${GLUE_VERSION}

RUN mvn -f $GLUE_HOME/pom.xml -DoutputDirectory=$GLUE_HOME/jars dependency:copy-dependencies

COPY src/config/spark/pom.xml $HOME/install/spark-pom.xml
RUN mvn -f $HOME/install/spark-pom.xml \
    -Dspark-version=$SPARK_VERSION \
    -Dscala-version=$SCALA_VERSION \
    -DoutputDirectory=${SPARK_HOME}/jars \
    dependency:copy-dependencies

RUN rm $GLUE_HOME/jars/javax.servlet-api-3* && \
    rm $GLUE_HOME/jars/netty-*

COPY src/config/hadoop/core-site.xml $SPARK_HOME/conf/
COPY src/config/spark/spark-env.sh $SPARK_HOME/conf/
COPY src/config/spark/spark-defaults.conf $SPARK_HOME/conf/
COPY src/config/aws_config $HOME/.aws/config

ENV PYTHONPATH $GLUE_HOME:$SPARK_HOME/python/lib/py4j-0.10.9-src.zip:$SPARK_HOME/python/:$PYTHONPATH

WORKDIR $HOME

ENTRYPOINT []
CMD ["/bin/sh"]

