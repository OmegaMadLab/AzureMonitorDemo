# Azure Monitor demo environment

In this repository you can find some scripts I used to demonstrate usage of Azure Monitor to realize some serverless automation on an Azure subscription.

- **environmentPreparation.ps1** creates some VMs and paas services needed to generate some logs and metrics
- **workloadGenerator.ps1** should be executed on Demo-WINVM1 to configure it as Hybrid Worker for Azure Automation and to generate some load on services created before
- **runbook.ps1** is a simple Azure Automation runbook that drop old log files on local disk of the hybrid worker
- **kqlExamples.ps1** contain an example of join between workspace tables

For some **Azure Functions** I used in this context, you can have a look to this **[repo](https://github.com/OmegaMadLab/StartingWithPoshAzureFunctions)**.

In **Slides** folder you can also find deck I used during presentations.
For a full recording of sessions, just look at my YouTube channel:

- **[Azure Saturday Pordenone 2019](https://youtu.be/ifHJATNmC9k)**, italian language 
