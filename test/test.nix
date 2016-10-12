{
  deployment1 = {
    kubernetes.controllers.test = {
      pod.containers.test = {
        image = "test2";
      };
    };

    kubernetes.services.test.ports = [{port = 1000;}];
  };

  deployment2 = {deployments, ...}: let
    deployment1 = deployments.deployment1.config;
  in {
    kubernetes.deployments.test = {
      pod.containers.test = {
        image = deployment1.kubernetes.controllers.test.pod.containers.test.image;
      };
    };

    kubernetes.services.test.ports = [{port = 1000;}];
  };
}
