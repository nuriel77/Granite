# Granite

Granite was an initiative to create a modular meta-scheduler that combines common HPC schedulers such as Slurm and Cloud resources provided by software such as OpenStack.
The common problem with scheduling in the cloud was that Slurm was bascially designed to utilize physical resources. What Granite aims at is creating a bridge between submitting jobs and scheduling them in the cloud. In a nutshell: jobs would be submitted to Slurm as they normally are. Granite would read the queue and spawn resources for each job. The resources would be cloud resources such as vm's or containers (Docker).

Granite is an engine that can load and work with different cloud technologies and schedulers and allow for custom scheduling algorithms to be loaded.

I have been working on this project in 2013, but had to abandon it because I stated working in other development companies and other projects.
