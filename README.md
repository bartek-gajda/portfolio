# portfolio
#
Several examples of my programs in Python and Ansible
## Ansible
- deploy-K8s-in-vmware

  Two playbooks for provisioning  kubernetes cluster in VMware, first one can be run from cli, second is to be run from AWX/Tower.
  
  They deploy VM form template, configure OS, prepare environment for K8s, lunch kubespray. Number of required VMs is specified by user.
  What's interesting - they use three inventories: 1. VMware hosts (static) 2. VMware VMs (created in playbook) 3. K8s nodes (created in playbook)
  
- deploy-barebone-servers-idrac 

  Sets of playbooks to deploy OS in barebone servers using Dell idrac and then install GPS software 
 
 ## Python
 - check_servers_using_nornir.py - program run several commands on remote servers using Nornir library
 - deploy-barebone-servers-idrac - program compare internal documentation in excel file containing IP assignements against public databases - RIPE whois

