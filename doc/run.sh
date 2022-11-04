#!/usr/bin/env sh
# shellcheck disable=SC2039

set -e

#prereq
#gcloud
#terraform
#psql

#config
start_path="$(pwd)"
project_id="hobby-367318"
ssh_key_path="$HOME/.ssh/google_compute_engine" #should be generated and added to keystore
ps_db=postgres

setup_cli=false
init_tf=true
upload_data=true
setup_ssh_key=true
execute_commands=true
execute_local_pg_commands=true
destroy_tf=true

#setup gcp cli
if [[ "$setup_cli" == "true" ]]; then
  gcloud auth application-default login #could be commented on second run
  gcloud config set project $project_id
  gcloud config list
fi

#infra with tf
perform_tf() {
  command=$1
  cd "$start_path/infra"
  TF_VAR_project_id=$project_id \
    TF_VAR_default_region=europe-west1 \
    TF_VAR_cluster_name=bd1 \
    terraform "$command" -auto-approve
  cd "$start_path"
}

#setup infra with tf
if [[ "$init_tf" == "true" ]]; then
  terraform init
  perform_tf apply
fi

#export terraform output
cd "$start_path/infra"
data_bucket_name="$(terraform output data-bucket-name | tr -d '"')"
dataproc_zone="$(terraform output dataproc-zone | tr -d '"')"
dataproc_master_node="$(terraform output dataproc-master-node | tr -d '"')"
cd "$start_path"

#upload required data to gcp storage
if [[ "$upload_data" == "true" ]]; then
  gsutil -m cp -r "$start_path/data" "gs://$data_bucket_name/data"
  gsutil -m cp -r "$start_path/jobs" "gs://$data_bucket_name/jobs"
fi

#add ssh key to dataproc node
if [[ "$setup_ssh_key" == "true" ]]; then
  gcloud compute os-login ssh-keys add --key=$ssh_key_path
fi

#execute commands on dataproc cluster node
dataproc_exec() {
  command=$1
  gcloud compute --project "$project_id" ssh --zone "$dataproc_zone" "$dataproc_master_node" --command "$command"
}

if [[ "$execute_commands" == "true" ]]; then
  dataproc_exec "mkdir ~/jobs && \
                 gsutil cp -r gs://$data_bucket_name/jobs ~/ && \
                 ls -la ~/jobs"

  dataproc_exec "mkdir ~/data && \
                 gsutil cp -r gs://$data_bucket_name/data ~/ && \
                 ls -la ~/data"

  dataproc_exec "unzip ~/data/UO.zip -d ~/data && \
                 unzip ~/data/FOP.zip -d ~/data && \
                 ls -la ~/data"

  dataproc_exec "hadoop fs -mkdir /tables_data && \
                 hadoop fs -mkdir /tables_data/UO && \
                 hadoop fs -mkdir /tables_data/FOP"

  dataproc_exec "hadoop fs -put ~/data/UO.csv /tables_data/UO/ && \
                 hadoop fs -put ~/data/FOP.csv /tables_data/FOP/"

  dataproc_exec "hive -e \"
                 drop table UO_table;
                 create external table UO_table
                 (name string, EDRPOU string, ADDRESS string, BOSS string, founders string, fio string, KVED string, stan string)
                 ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
                 STORED AS TEXTFILE LOCATION '/tables_data/UO/';\""

  dataproc_exec "hive -e \"
                drop table FOP_table;
                create external table FOP_table
                (fio string, address string, kved string, stan string)
                ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
                STORED AS TEXTFILE LOCATION '/tables_data/FOP/';\""

  dataproc_exec "hive -e \"select count(*) from UO_table;\"" # Time taken: 91.914 seconds
  dataproc_exec "hive -e \"select name, edrpou, address, row_number()
                           over (partition by address order by edrpou)
                           as rn_by_place
                           from UO_table
                           limit 20;\" > out" # Time taken: 49.05 seconds
  dataproc_exec "hive -e \"select * from UO_table uo join FOP_table fop on
                           uo.address=fop.address
                           limit 20;\" > out" # Time taken: 113.145 seconds

  dataproc_exec "hadoop jar ~/jobs/hadoop-examples-1.2.1.jar wordcount /tables_data/UO ~/data/word_count_output.out"
fi

if [[ "$execute_local_pg_commands" == "true" ]]; then
  unzip -o "$start_path/data/UO.zip" -d "$start_path/tmp"
  unzip -o "$start_path/data/FOP.zip" -d "$start_path/tmp"

  psql -d "$ps_db" -c "drop table if exists UO_table;
                       create table UO_table
                       (name varchar, EDRPOU varchar, ADDRESS varchar, BOSS varchar, founders varchar, fio varchar, KVED varchar, stan varchar);
                       copy UO_table FROM '$start_path/tmp/UO.csv' QUOTE '\"' ESCAPE E'\\'' CSV;"

  psql -d "$ps_db" -c "drop table if exists FOP_table;
                       create table FOP_table
                       (fio varchar, address varchar, kved varchar, stan varchar);
                       copy FOP_table FROM '$start_path/tmp/FOP.csv' QUOTE '\"' ESCAPE E'\\'' CSV;"

  time psql -d "$ps_db" -c "select count(*) from UO_table" # Time taken: real 0m4.481s, user 0m0.003s, sys 0m0.002s
  time psql -d "$ps_db" -c "select name, edrpou, address, row_number()
                            over (partition by address order by edrpou)
                            as rn_by_place
                            from UO_table
                            limit 20;" >"$start_path/tmp/out" # Time taken: real 0m5.056s, user 0m0.004s, sys 0m0.005s
  time psql -d "$ps_db" -c "select * from UO_table uo join FOP_table fop on
                            uo.address=fop.address
                            limit 20;" >"$start_path/tmp/out" # Time taken: real 0m9.771s, user 0m0.005s, sys 0m0.003s
fi

#destroy infra with tf
if [[ "$destroy_tf" == "true" ]]; then
  perform_tf destroy
fi
