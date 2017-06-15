{ lib, pkgs }:

with lib;

let
  flattenAttrs = attrs: listToAttrs (
    collect (val: val ? "name" && val ? "value") (
      mapAttrsRecursive (path: value:
        nameValuePair (concatStringsSep "." path) value
      ) attrs)
  );


  mkResource = apiVersion: kind: { inherit apiVersion kind; };

  mkMeta = resource: {
    metadata.name = resource.name;
    metadata.labels = resource.labels;
    metadata.annotations = resource.annotations // {
      "x-truder.net/dependencies" = concatStringsSep "," resource.dependencies;
      "x-truder.net/kind" = "nix-kubernetes";
      "x-truder.net/version" = "v1";
    };
  };

  mkNsMeta = resource: recursiveUpdate (mkMeta resource) {
    metadata.namespace = resource.namespace;
  };

  mkSpecMeta = resource: {
    metadata.labels = resource.labels;
    metadata.annotations = resource.annotations;
  };

  mkCommand = cmd: if isString cmd then ["sh" "-c" cmd] else cmd;

  filterNull = attrs: (filterAttrs (n: v: v != null) attrs);

  mkProbe = probe: {
    initialDelaySeconds = probe.initialDelaySeconds;
    timeoutSeconds = probe.timeoutSeconds;
  } // (optionalAttrs (probe.httpGet.path != null) {
    httpGet = probe.httpGet;
  }) // (optionalAttrs (probe.tcpSocket.port != null) {
    tcpSocket = probe.tcpSocket;
  }) // (optionalAttrs (probe.exec.command != null) {
    exec = probe.exec;
  });

  mkContainer = container: {
    name = container.name;
    image = container.image;
    imagePullPolicy = "Always";
    securityContext = container.security;
    ports = map (port: {
      inherit (port) containerPort protocol;
    } // (optionalAttrs (port.name != null) {
      inherit (port) name;
    }) // (optionalAttrs (port.hostPort != null) {
      inherit (port) hostPort;
    })) container.ports;
    volumeMounts = map (volume: ({
      inherit (volume) name mountPath readOnly;
    } // (optionalAttrs (volume.subPath != null) {
      subPath = volume.subPath;
    }))) container.mounts;
    env = mapAttrsToList (name: value: {
      inherit name;
    } // (if (isAttrs value) then {
      valueFrom = value;
    } else if (isString value && hasPrefix "secret:" value) then {
      valueFrom.secretKeyRef = {
        name = head (splitString ":" (removePrefix "secret:" value));
        key = head (tail (splitString ":" (removePrefix "secret:" value)));
      };
    } else if (isString value && hasPrefix "configMap:" value) then {
       valueFrom.configMapKeyRef = {
        name = head (splitString ":" (removePrefix "configMap:" value));
        key = head (tail (splitString ":" (removePrefix "configMap:" value)));
      };
    } else {
      value = toString value;
    })) container.env;
    tty = container.tty;
    stdin = container.stdin;
    resources.limits = filterNull container.limits;
    resources.requests = filterNull container.requests;
  } // (optionalAttrs (container.command != null) {
    command = mkCommand container.command;
  }) // (optionalAttrs (container.args != null) {
    args = mkCommand container.args;
  }) // (optionalAttrs (container.postStart.command != null) {
    lifecycle.postStart.exec.command = mkCommand container.postStart.command;
  }) // (optionalAttrs (container.livenessProbe.enable) {
    livenessProbe = mkProbe container.livenessProbe;
  }) // (optionalAttrs (container.readinessProbe.enable) {
    readinessProbe = mkProbe container.readinessProbe;
  }) // (optionalAttrs (container.workdir != null) {
    workingDir = container.workdir;
  });

  mkVolume = volume: {
    name = volume.name;
    ${volume.type} = volume.options;
  };

  mkPodSpec = resource: {
    spec = {
      nodeSelector = resource.nodeSelector;

      containers = mapAttrsToList (name: container:
        mkContainer container
      ) resource.containers;

      volumes = mapAttrsToList (name: volume:
        mkVolume volume
      ) resource.volumes;

      restartPolicy = resource.restartPolicy;

      imagePullSecrets = map (secret: {
        name = secret;
      }) resource.imagePullSecrets;

    } // (optionalAttrs (resource.serviceAccountName != null) {serviceAccountName = resource.serviceAccountName;});
  };

  mkControllerSpec = rc: {
    spec = {
      replicas = rc.replicas;
      selector = rc.selector;
      template = (mkSpecMeta rc.pod) // (mkPodSpec rc.pod);
    };
  };

  mkDeploymentSpec = deployment: {
    spec = {
      replicas = deployment.replicas;
      template = (mkSpecMeta deployment.pod) // (mkPodSpec deployment.pod);
    };
  };

  mkDaemonSetSpec = daemon: {
    spec = {
      template = (mkSpecMeta daemon.pod) // (mkPodSpec daemon.pod);
    };
  };

  mkServiceSpec = service: {
    spec = {
      ports = map (port: {
        port = port.port;
        targetPort = port.targetPort;
        protocol = port.protocol;
      } // (optionalAttrs (port.name != null) {
        name = port.name;
      } // (optionalAttrs (port.nodePort != null) {
        nodePort = port.nodePort;
      }))) service.ports;
      selector = service.selector;
      type = service.type;
    } // (optionalAttrs (service.clusterIP != null) {
      clusterIP = service.clusterIP;
    }) // (optionalAttrs (service.externalIPs != null) {
      externalIPs = service.externalIPs;
    });
  };

  mkPvcSpec = pvc: {
    spec = {
      accessModes = pvc.accessModes;
      resources = {
        requests = {
          storage = pvc.size;
        };
      };
    };
  };

  mkSecretData = secret: {
    data = mapAttrs (name: secret:
      builtins.readFile (pkgs.stdenv.mkDerivation {
        name = "secret-${name}";
        buildCommand = ''
          cat ${secret} | ${pkgs.coreutils}/bin/base64 -w0 > $out
        '';
      })
    ) secret.secrets;
    type = secret.type;
  };

  mkIngressSpec = ing: {
    spec = {
      rules = mapAttrsToList (name: rule: {
        host = rule.host;
        http.paths = mapAttrsToList (name: path: {
          path = path.path;
          backend = path.backend;
        }) rule.http.paths;
      }) ing.rules;
    } // (optionalAttrs (ing.tls.secretName != null) {
      tls = [
        ({secretName = ing.tls.secretName;}
          // (optionalAttrs (ing.tls.hosts != null) {hosts = ing.tls.hosts;}))
      ];
    });
  };

  mkJobSpec = job: {
    spec.template = (mkSpecMeta job.pod) // (mkPodSpec job.pod);
    spec.activeDeadlineSeconds = job.activeDeadlineSeconds;
  };

  mkScheduledJobSpec = scheduledJob: {
    spec = {
      suspend = !scheduledJob.enable;
      schedule = scheduledJob.schedule;
      jobTemplate = (mkSpecMeta scheduledJob.job) // (mkJobSpec scheduledJob.job);
      concurrencyPolicy = scheduledJob.concurrencyPolicy;
    };
  };

  mkNetworkPolicySpec = policy: {
    spec = {
      podSelector.matchLabels = policy.podSelector.matchLabels;
      ingress = mapAttrsToList (name: rule: {
        from = (optionals (rule.namespaceSelector.matchLabels != null) [{
          namespaceSelector.matchLabels = rule.namespaceSelector;
        }]) ++ (optionals (rule.podSelector.matchLabels != null) [{
          podSelector.matchLabels = rule.podSelector.matchLabels;
        }]);
        ports = rule.ports;
      }) policy.ingress;
    };
  };

  mkRoleSpec = role: {
    rules = map (rule: (optionalAttrs (cfg.apiGroups != null) {
      apiGroups = rule.apiGroups;
    }) // (optionalAttrs (cfg.resources != null) {
      resources = rule.resources;
    }) // (optionalAttrs (cfg.verbs != null) {
      verbs = rule.verbs;
    }) // (optionalAttrs (cfg.nonResourceURLs != null) {
      nonResourceURLs = rule.nonResourceURLs;
    })) role.rules;
  };

  mkRoleBindingSpec = binding: {
    subjects = map (binding: filterAttrs (n: v: n != "_module") binding) binding.subjects;
    roleRef = binding.roleRef;
  };

  mkServiceAccountSpec = serviceAccount: {
  };

  mkConfigMapSpec = configMap: {
    data = flattenAttrs configMap.data;
  };

  mkStatefulSetSpec = statufulset: {
    spec = {
      replicas = statufulset.replicas;
      serviceName = statufulset.serviceName;
      template = (mkSpecMeta statufulset.pod) // (mkPodSpec statufulset.pod);
      volumeClaimTemplates =
        mapAttrsToList (name: claimTemplate:
          (mkNsMeta claimTemplate) // (mkPvcSpec claimTemplate)
        ) statufulset.volumeClaimTemplates;
    };
  };

  mkPetSetSpec = petset: mkStatefulSetSpec petset;

  mkCustomResourceExtra = customResource:
    mapAttrs (n: v: v) customResource.extra;

in {
  mkNamespace = namespace:
    (mkResource "v1" "Namespace") // (mkMeta namespace);

  mkPod = pod:
    (mkResource "v1" "Pod") // (mkNsMeta pod) //
    (mkPodSpec pod);

  mkService = service:
    (mkResource "v1" "Service") // (mkNsMeta service) //
    (mkServiceSpec service);

  mkController = controller:
    (mkResource "v1" "ReplicationController") // (mkNsMeta controller) //
    (mkControllerSpec controller);

  mkDeployment = deployment:
    (mkResource "extensions/v1beta1" "Deployment") // (mkNsMeta deployment) //
    (mkDeploymentSpec deployment);

  mkDaemonSet = daemon:
    (mkResource "extensions/v1beta1" "DaemonSet") // (mkNsMeta daemon) //
    (mkDaemonSetSpec daemon);

  mkScheduledJob = scheduledJob:
    (mkResource "batch/v2alpha1" "ScheduledJob") // (mkNsMeta scheduledJob) //
    (mkScheduledJobSpec scheduledJob);

  mkJob = job:
    (mkResource "extensions/v1beta1" "Job") // (mkNsMeta job) //
    (mkJobSpec job);

  mkIngress = ingress:
    (mkResource "extensions/v1beta1" "Ingress") // (mkNsMeta ingress) //
    (mkIngressSpec ingress);

  mkSecret = secret:
    (mkResource "v1" "Secret") // (mkNsMeta secret) //
    (mkSecretData secret);

  mkPvc = pvc:
    (mkResource "v1" "PersistentVolumeClaim") // (mkNsMeta pvc) //
    (mkPvcSpec pvc);

  mkRole = role:
     (mkResource "rbac.authorization.k8s.io/v1beta1" "Role") // (mkNsMeta role) //
     (mkRoleSpec role);

  mkClusterRole = role:
     (mkResource "rbac.authorization.k8s.io/v1beta1" "ClusterRole") // (mkNsMeta role) //
     (mkRoleSpec role);

  mkRoleBinding = role:
     (mkResource "rbac.authorization.k8s.io/v1beta1" "RoleBinding") // (mkNsMeta role) //
     (mkRoleBindingSpec role);

  mkClusterRoleBinding = role:
    (mkResource "rbac.authorization.k8s.io/v1beta1" "ClusterRoleBinding") // (mkMeta role) //
    (mkRoleBindingSpec role);

  mkServiceAccount = serviceAccount:
    (mkResource "v1" "ServiceAccount") // (mkNsMeta serviceAccount) //
    (mkServiceAccountSpec serviceAccount);

  mkConfigMap = configMap:
    (mkResource "v1" "ConfigMap") // (mkNsMeta configMap) //
    (mkConfigMapSpec configMap);

  mkPetSet = petset:
    (mkResource "apps/v1alpha1" "PetSet") // (mkNsMeta petset) //
    (mkPetSetSpec petset);

  mkStatefulSet = statefulset:
    (mkResource "apps/v1beta1" "StatefulSet") // (mkNsMeta statefulset) //
    (mkStatefulSetSpec statefulset);

  mkNetworkPolicy = networkpolicy:
    (mkResource "extensions/v1beta1" "NetworkPolicy") // (mkNsMeta networkpolicy) //
    (mkNetworkPolicySpec networkpolicy);

  mkCustomResource = customResource:
    (mkResource customResource.apiVersion customResource.kind) //
    (mkMeta customResource) //
    (mkCustomResourceExtra customResource);
}
