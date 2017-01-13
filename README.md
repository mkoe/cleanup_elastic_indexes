# Automatically Cleaning up Indexes in Elasticsearch

A bashscript to close and delete indexes of elasticsearch automatically

## Requirements

   * bc
   * jq
   * awk

## Installation 

   * Just put the Script where ever you would like to have it on your system
   * configure the Variables within the Configuration Section
   * create a cronjob

```
30      0       *       *       *       root /etc/ddosproxy/scripts/cleanup_elastic.sh
```






