## Big data lab #1

#### Project structure
* data - empty folder to place (FOP.zip & UO.zip)
* doc - folder that contains main sh script
* infra - folder with terraform infrastructure description
* jobs - folder with hadoop sample jar
* log - execution results
* tmp - empty folder to store execution temporary data

#### Protocol data
* SQL queries and performance on Hadoop and Postgres are present in ```doc/run.sh```
* Hadoop's logs are present in ```log/run1.log```

#### Run instructions
1. install ```gcloud```, ```terraform```, ```psql```
2. create gcp project
3. generate ssh certificate
4. configure and run ```doc/run.sh > log/run.log```
