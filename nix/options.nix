{ config, pkgs, lib, ... }:

with lib;

let

  cfg = config.kubernetes;

  metaOptions = {name, config, ...}: {
    options = {
      name = mkOption {
        description = "Name of the resource";
        type = types.str;
        default = name;
      };

      labels = mkOption {
        description = "Pod labels";
        type = types.attrsOf types.str;
        default = {};
      };

      annotations = mkOption {
        description = "Pod annotation";
        type = types.attrsOf types.str;
        default = {};
      };

      namespace = mkOption {
        description = "Resource namespace";
        type = types.str;
        default = cfg.defaultNamespace;
      };

      dependencies = mkOption {
        description = "Resource dependencies";
        type = types.listOf types.str;
        default = [];
      };
    };
  };

  containerOptions = { name, config, ... }: {
    options = {
      name = mkOption {
        description = "Name of the container";
        default = name;
        type = types.str;
      };

      enable = mkOption {
        description = "Whether to enable container";
        default = true;
        type = types.bool;
      };

      image = mkOption {
        description = "Image to use";
        type = types.str;
      };

      command = mkOption {
        description = "Command to run";
        type = types.nullOr (types.either (types.listOf types.str) types.str);
        default = null;
      };

      args = mkOption {
        description = "Arguments to command";
        type = types.nullOr (types.either (types.listOf types.str) types.str);
        default = null;
      };

      env = mkOption {
        description = "Environment variables to set";
        default = {};
        type = types.attrsOf types.unspecified;
      };

      postStart = {
        command = mkOption {
          description = "Command to execute in post start phase";
          type = types.nullOr (types.either (types.listOf types.str) types.str);
          default = null;
        };
      };

      security = {
        capabilities = {
          add = mkOption {
            description = "Capabilites to add";
            type = types.listOf types.str;
            default = [];
          };
        };

        privileged = mkOption {
          description = "Whether to run container as privileged";
          type = types.bool;
          default = false;
        };
      };

      ports = mkOption {
        description = "Ports exposed by pod";
        type = types.listOf types.optionSet;
        default = [];

        options = { config, ... }: {
          options = {
            name = mkOption {
              description = "Name of the port";
              type = types.nullOr types.str;
              default = null;
            };

            protocol = mkOption {
              description = "Protocol to use";
              default = "TCP";
              type = types.enum ["TCP" "UDP"];
            };

            port = mkOption {
              description = "Port to expose";
              type = types.int;
            };

            containerPort = mkOption {
              description = "Port in container";
              default = config.port;
              type = types.int;
            };
          };
        };
      };

      mounts = mkOption {
        description = "Volumes mounted in pod";
        type = types.listOf types.optionSet;
        default = [];

        options = {
          name = mkOption {
            description = "Name of the volume";
            type = types.str;
          };

          mountPath = mkOption {
            description = "Mount path of volume";
            type = types.path;
          };
        };
      };

      requests = {
        memory = mkOption {
          description = "Limit memory for container";
          type = types.nullOr types.str;
          example = "128Mi";
          default = null;
        };

        cpu = mkOption {
          description = "Limit cpu for container";
          type = types.nullOr types.str;
          example = "500m";
          default = null;
        };
      };

      limits = {
        memory = mkOption {
          description = "Limit memory for container";
          type = types.nullOr types.str;
          example = "128Mi";
          default = null;
        };

        cpu = mkOption {
          description = "Limit cpu for container";
          type = types.nullOr types.str;
          example = "500m";
          default = null;
        };
      };

      livenessProbe = {
        httpGet = {
          path = mkOption {
            description = "Http check path";
            type = types.nullOr types.str;
            default = null;
          };

          port = mkOption {
            description = "Http check port";
            type = types.int;
            default = 80;
          };
        };

        initialDelaySeconds = mkOption {
          description = "Initial delay before checking";
          default = 30;
          type = types.int;
        };

        timeoutSeconds = mkOption {
          description = "Check timeout";
          default = 5;
          type = types.int;
        };
      };
    };
  };

  volumeOptions = { name, config, ... }: {
    options = {
      name = mkOption {
        description = "Name of the volume";
        type = types.str;
        default = name;
      };

      type = mkOption {
        description = "Volume type";
        type = types.str;
      };

      options = mkOption {
        description = "Volume options";
        type = types.attrs;
        default = {};
      };
    };
  };

  podTemplateOptions = {
    nodeSelector = mkOption {
      description = "Node selector where to put pod";
      type = types.attrsOf types.str;
      default = {};
    };

    containers = mkOption {
      description = "Pod containers";
      type = types.attrsOf types.optionSet;
      options = [ containerOptions ];
    };

    volumes = mkOption {
      description = "Pod volumes";
      type = types.attrsOf types.optionSet;
      options = [ volumeOptions ];
      default = {};
    };

    restartPolicy = mkOption {
      description = "Pod restart policy";
      type = types.enum ["Always" "OnFailure" "Never"];
      default = "Always";
    };

    imagePullSecrets = mkOption {
      description = "Name of the secret to use for pulling docker image";
      type = types.listOf types.str;
      default = [];
    };
  };

  podOptions = { name, config, ... }: {
    options = podTemplateOptions;
    config = mkDefault cfg.defaults.pods;
  };

  deploymentOptions = { name, config, ... }: {
    options = {
      enable = mkOption {
        description = "Whether to enable deployment";
        default = false;
        type = types.bool;
      };

      replicas = mkOption {
        description = "Number of replicas to run";
        default = 1;
        type = types.int;
      };

      pod = podTemplateOptions // {
        labels = mkOption {
          description = "Pod labels";
          type = types.attrsOf types.str;
          default = {};
        };

        annotations = mkOption {
          description = "Pod annotation";
          type = types.attrsOf types.str;
          default = {};
        };
      };
    };

    config = mkMerge [{
      pod.labels.name = mkDefault config.name;
    } (mkDefault cfg.defaults.deployments)];
  };

  replicationControllerOptions = { name, config, ... }: {
    options = {
      enable = mkOption {
        description = "Whether to enable controller";
        default = false;
        type = types.bool;
      };

      selector = mkOption {
        description = "Pod selector";
        type = types.attrsOf types.str;
        default = { name = config.name; };
      };

      replicas = mkOption {
        description = "Number of replicas to run";
        default = 1;
        type = types.int;
      };

      pod = podTemplateOptions // {
        labels = mkOption {
          description = "Pod labels";
          type = types.attrsOf types.str;
          default = {};
        };

        annotations = mkOption {
          description = "Pod annotation";
          type = types.attrsOf types.str;
          default = {};
        };
      };
    };

    config = mkMerge [{
      pod.labels.name = mkDefault config.name;
    } (mkDefault cfg.defaults.replicationcontrollers)];
  };

  serviceOptions = { name, config, ... }: {
    options = {
      type = mkOption {
        description = "Service type (ClusterIP, NodePort, LoadBalancer)";
        type = types.enum ["ClusterIP" "NodePort" "LoadBalancer"];
        default = "ClusterIP";
      };

      ports = mkOption {
        type = types.listOf types.optionSet;
        options = { config, ... }: {
          options = {
            name = mkOption {
              description = "Name of the port";
              type = types.nullOr types.str;
              default = null;
            };

            protocol = mkOption {
              description = "Protocol to use";
              default = "TCP";
              type = types.enum ["TCP" "UDP"];
            };

            port = mkOption {
              description = "Port to expose";
              type = types.int;
            };

            targetPort = mkOption {
              default = config.port;
              type = types.int;
              description = "Pod target port";
            };

            nodePort = mkOption {
              default = null;
              type = types.nullOr types.int;
              description = "Port on the node";
            };
          };
        };
      };

      selector = mkOption {
        description = "Service selector";
        type = types.attrsOf types.str;
        default = { inherit name; };
      };
    };
  };

  namespaceOptions = {};

  pvcOptions = { name, config, ... }: {
    options = {
      size = mkOption {
        description = "Size of storage requested by persistent volume claim";
        type = types.str;
        default = "1G";
        example = "10G";
      };

      accessModes = mkOption {
        description = "Requested acces modes";
        type = types.listOf (types.enum ["ReadWriteOnce" "ReadWriteMany"]);
        default = ["ReadWriteOnce"];
      };
    };

    config = mkDefault cfg.defaults.pvc;
  };

  secretOptions = { name, config, ... }: {
    options = {
      secrets = mkOption {
        description = "Files to include in secret";
        type = types.attrs;
      };
    };
  };

  ingressOptions = { name, config, ... }: {
    options = {
      tls = {
        secretName = mkOption {
          description = "Name of the tls secret";
          type = types.nullOr types.str;
          default = null;
        };
      };

      rules = mkOption {
        description = "Attribute set of rules";
        type = types.attrsOf types.optionSet;
        options = { name, config, ... }: {
          options = {
            host = mkOption {
              description = "Ingress host";
              type = types.nullOr types.str;
            };

            http.paths = mkOption {
              description = "Attribute set of paths";
              type = types.attrsOf types.optionSet;
              options = { name, config, ... }: {
                options = {
                  path = mkOption {
                    description = "Path to route";
                    type = types.str;
                    default = name;
                  };

                  backend.serviceName = mkOption {
                    description = "Name of the service to route to";
                    type = types.str;
                  };

                  backend.servicePort = mkOption {
                    description = "Service port to route to";
                    type = types.int;
                    default = 80;
                  };
                };
              };
            };
          };
        };
      };
    };
  };

  jobOptions = {
    pod = podTemplateOptions // {
      labels = mkOption {
        description = "Pod labels";
        type = types.attrsOf types.str;
        default = {};
      };

      annotations = mkOption {
        description = "Pod annotation";
        type = types.attrsOf types.str;
        default = {};
      };
    };
  };

  scheduledJobOptions = { name, config, ... }: {
    options = {
      enable = mkOption {
        description = "Whether to enable scheduled job";
        default = true;
        type = types.bool;
      };

      schedule = mkOption {
        description = "job schedule";
        type = types.str;
      };

      job = jobOptions // {
        labels = mkOption {
          description = "Pod labels";
          type = types.attrsOf types.str;
          default = {};
        };

        annotations = mkOption {
          description = "Pod annotation";
          type = types.attrsOf types.str;
          default = {};
        };
      };
    };

    config = {
      job.labels.scheduled-job-name = name;
      job.pod.labels.scheduled-job-name = name;
    };
  };

in {
  options.kubernetes = {
    namespaces = mkOption {
      type = types.attrsOf types.optionSet;
      options = [ metaOptions namespaceOptions ];
      description = "Attribute set of namespaces";
      default = {};
    };

    pods = mkOption {
      type = types.attrsOf types.optionSet;
      options = [ metaOptions podOptions ];
      description = "Attribute set of pods";
      default = {};
    };

    controllers = mkOption {
      type = types.attrsOf types.optionSet;
      options = [ metaOptions replicationControllerOptions ];
      description = "Attribute set of controllers";
      default = {};
    };

    deployments = mkOption {
      type = types.attrsOf types.optionSet;
      options = [ metaOptions deploymentOptions ];
      description = "Attribute set of deployments";
      default = {};
    };

    services = mkOption {
      type = types.attrsOf types.optionSet;
      options = [ metaOptions serviceOptions ];
      description = "Attribute set of services";
      default = {};
    };

    pvc = mkOption {
      type = types.attrsOf types.optionSet;
      options = [ metaOptions pvcOptions ];
      description = "Attribute set of persistent volume claims";
      default = {};
    };

    secrets = mkOption {
      type = types.attrsOf types.optionSet;
      options = [ metaOptions secretOptions ];
      description = "Attribute set of secrets";
      default = {};
    };

    ingress = mkOption {
      type = types.attrsOf types.optionSet;
      options = [ metaOptions ingressOptions ];
      description = "Attribute set of ingress";
      default = {};
    };

    jobs = mkOption {
      type = types.attrsOf types.optionSet;
      options = [ metaOptions jobOptions ];
      description = "Attribute set of jobs";
      default = {};
    };

    scheduledJobs = mkOption {
      type = types.attrsOf types.optionSet;
      options = [ metaOptions scheduledJobOptions ];
      description = "Attribute set of schedule job definitions";
      default = {};
    };

    defaultNamespace = mkOption {
      type = types.str;
      default =
        if length (attrNames cfg.namespaces) >= 1
        then (getAttr (head (attrNames cfg.namespaces)) cfg.namespaces).name
        else "default";
      description = "Default namespace to put resources in";
    };

    defaults = {
      allPods = mkOption {
        description = "Default config applied to all pods";
        type = types.attrs;
        default = {};
      };

      pods = mkOption {
        description = "Default config applied to pods";
        type = types.attrs;
        default = cfg.defaults.allPods;
      };

      jobs = mkOption {
        description = "Default config applied to jobs";
        type = types.attrs;
        default = {
          pod = cfg.defaults.allPods;
        };
      };

      replicationcontrollers = mkOption {
        description = "Default config applied to replication controllers";
        type = types.attrs;
        default = {
          pod = cfg.defaults.allPods;
        };
      };

      deployments = mkOption {
        description = "Default config applied to deployments";
        type = types.attrs;
        default = {
          pod = cfg.defaults.allPods;
        };
      };

      pvc = mkOption {
        description = "Default config applied to persistent volume claims";
        type = types.attrs;
        default = {};
      };
    };
  };
}
