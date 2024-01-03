#!/bin/bash
usage='Usage: ./go0init.sh project_name' 
attention='project_name should not be "demoxyz", "jinquan", "jinquan7"'
if [ $# -ne 1 ]; then
        echo $usage
        echo $attention
else
project=$1

cat << EOF > $project/Dockerfile
FROM ${ARCH}alpine:3.18 as container
MAINTAINER jinquan jinquan7@foxmail.com
LABEL Description="go-zero application."
USER root
RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.cloud.tencent.com/g' /etc/apk/repositories;
RUN  apk add -U bash tzdata gettext tree curl busybox-extras iputils netcat-openbsd \
     && cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
     && mkdir -p /home/jinquan \ 
     && addgroup -g 2001 safe \
     && adduser -u 1001 -D -s /bin/bash -h /home/jinquan -G safe jinquan 
COPY entrypoint.sh /home/jinquan/entrypoint.sh
RUN  chmod +x /home/jinquan/entrypoint.sh; \
     chown jinquan:safe -R /home/jinquan;
USER jinquan
WORKDIR /home/jinquan
ENV app_routine=demo
COPY demo /home/jinquan/app/demo
COPY etc /home/jinquan/app/etc/
RUN  tree -acs /home/jinquan
EXPOSE 8888
ENTRYPOINT ["/home/jinquan/entrypoint.sh"]
EOF

sed -i "s/demo/$project/g" $project/Dockerfile

echo "[add] $project/Dockerfile"

cat << EOF > $project/entrypoint.sh
#!/bin/bash
tree -acs /home/jinquan/
exec /home/jinquan/app/\$app_routine
EOF

echo "[add] $project/entrypoint.sh"

mkdir -p $project/helm
helm create $project/helm/$project

cat << EOF >> $project/helm/$project/values.yaml

myconf:
  enabled: true
  Name: $project-api
  Host: 0.0.0.0
  Port: 8888
  Deploy:
    HostType: "Kubernetes Pod"
    Version: "go-zero $project v1.0"
EOF
sed -i 's/port: 80/port: 8888/g' $project/helm/$project/values.yaml
echo "[modify] $project/helm/$project/values.yaml"

cat << EOF > $project/etc/myconf.yaml
Name: $project-api
Host: 0.0.0.0
Port: 8888
deploy:
  hosttype: "VMware VM"
  version: "go-zero $project v1.0"
EOF

echo "[add] $project/etc/myconf.yaml"

cat << EOF > $project/helm/$project/templates/configmap.yaml
{{- if .Values.myconf.enabled -}}
{{- \$fullName := include "$project.fullname" . -}}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ \$fullName }}
  labels:
    {{- include "$project.labels" . | nindent 4 }}
data:
  myconf.yaml: |
    {{- include "myconf.yaml" . | nindent 4 }}
{{- end }}
EOF

echo "[add] $project/helm/$project/templates/configmap.yaml"

cat << EOF >> $project/helm/$project/templates/_helpers.tpl

{{/*
myconf configmap yaml template.
*/}}
{{- define "myconf.yaml" -}}
Name: $project-api
Host: 0.0.0.0
Port: 8888
deploy:
  hosttype: {{ .Values.myconf.Deploy.HostType }}
  version: {{ .Values.myconf.Deploy.Version }}
{{- end }}
EOF

echo "[modify] $project/helm/$project/templates/_helpers.tpl"

sed -i 's/      containers:/ \
      terminationGracePeriodSeconds: 0  ## jinquan added. \
      {{- if .Values.myconf.enabled }}  ## jinquan added. \
      volumes: \
        - name: myconf \
          configMap: \
            name: {{ include "demoxyz.fullname" . }} \
      {{- end }}\n&/g' $project/helm/$project/templates/deployment.yaml
sed -i "s/demoxyz/$project/" $project/helm/$project/templates/deployment.yaml

sed -i 's/          ports:/ \
          {{- if or .Values.myconf.enabled }}  ## jinquan added. \
          volumeMounts: \
          {{- end }} \
          {{- if .Values.myconf.enabled }}  ## jinquan added. \
          - name: myconf \
            mountPath: \/home\/jinquan\/app\/etc\/myconf.yaml \
            subPath: myconf.yaml \
          {{- end }}\n&/g' $project/helm/$project/templates/deployment.yaml

sed -i "{:begin;  /resources:/! { $! { N; b begin }; }; s/livenessProbe:.*resources:/ /; };" $project/helm/$project/templates/deployment.yaml

sed -i 's/            {{- toYaml .Values.resources | nindent 12 }}/          resources: \
            {{- toYaml .Values.resources | nindent 12 }}/g' $project/helm/$project/templates/deployment.yaml

sed -i "s/              containerPort: 80/              containerPort: {{ .Values.myconf.Port }}  ## jinquan modified./" $project/helm/$project/templates/deployment.yaml

echo "[modify] $project/helm/$project/templates/deployment.yaml"

mkdir -p $project/internal/jinquan/

cat << EOF > $project/internal/jinquan/myconf.go
package jinquan

import (
  "log"
  "io/ioutil"
  "gopkg.in/yaml.v2"
  _ "flag"
   "path/filepath"
   "os"
)

type ST_MyConf struct {
  Deploy struct {
    HostType string \`yaml:"hosttype"\`
    Version string \`yaml:"version"\`
  } \`yaml:"deploy"\`
}

func load_myconf_file(f string) *ST_MyConf {
  dat,err := ioutil.ReadFile(f)
  if err != nil {
    log.Println(err.Error())
    return nil
  }
  var cfg ST_MyConf
  err = yaml.Unmarshal(dat, &cfg)
  if err != nil {
    log.Println(err.Error())
    return nil
  }
  return &cfg
}

var (
  MyConf *ST_MyConf
)

func LocateMyconf(myconf string) string {
  exe_dir,_ := filepath.Abs(filepath.Dir(os.Args[0]))
  config_file := exe_dir+"/"+myconf
  log.Printf("load configuration file: %s\n", config_file)
  return config_file
}

func InitMyconf(myconf string) {
  MyConf = load_myconf_file(LocateMyconf(myconf))
}
EOF
echo "[add] $project/internal/jinquan/myconf.go"

sed -i "s/\"$project\/internal\/svc\"/ \
\"$project\/internal\/svc\"\n \
\"$project\/internal\/jinquan\"/g" $project/$project.go

sed -i 's/flag.Parse()/ \
flag.Parse() \
jinquan.InitMyconf(*configFile)/g' $project/$project.go
sed -i 's/conf.MustLoad(\*configFile, \&c)/conf.MustLoad(jinquan.LocateMyconf(\*configFile), \&c)/g' $project/$project.go
sed -i "s/\"etc\/$project-api.yaml\"/\"etc\/myconf.yaml\"/g" $project/$project.go
echo "[modify] $project/$project.go"

fi
