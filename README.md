# Running AWS Glue ETL locally

### Pre-requisites
* docker/docker-compose


### Config files

* src/config/hadoop/core-site.xml - Updated to point to local s3 emulator
* src/config/spark/spark-defaults.conf - Glue jars were added to classpath
* src/config/spark/pom.xml - This is not really required. It was added just in case you want to read/write Avro format via Spark not via Glue libs


### Build
```
docker compose -f docker-compose.yml build --progress plain

```

### Launch container
```
docker compose -f docker-compose.yml run \
--service-ports --rm \
--volume ./src/data:/root/data \
glue /bin/bash

```

### Create test bucket
```
aws s3 mb "s3://sample-bucket" --region ap-southeast-2 --endpoint-url=http://s3:9000
```

### Upload some data
```
aws s3 cp ./data/addresses.csv s3://sample-bucket/sample/ --endpoint-url=http://s3:9000
```


### Test commands
```
pyspark

import sys
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.utils import getResolvedOptions
from awsglue.dynamicframe import DynamicFrame
import pyspark.sql.functions as F
import pytz

# read from local bucket
df = spark.read.csv("s3://sample-bucket/sample/", header=True, sep=",", inferSchema=True)

df_write = df.select("firstName", "email", "phoneNumber")

df_write.show()

# try out some glue libs
glue_context= GlueContext(spark.sparkContext)
spark_session = glue_context.spark_session
logger = glue_context.get_logger()
job = Job(glue_context)
job.init("test_avro")

member_dyn = DynamicFrame.fromDF(df_write, glue_context, "member_dyn")

glue_context.write_dynamic_frame_from_options(
    frame=member_dyn,
    connection_type = "s3", 
    connection_options = {
        "path": "s3://sample-bucket/avro"
     }, 
    format = "avro", 
    format_options={
        "version": "1.8"
    } 
)

job.commit()

# read avro via spark
df_avro = spark_session.read.format("avro").load("s3://sample-bucket/avro")

df_avro.show()

```
