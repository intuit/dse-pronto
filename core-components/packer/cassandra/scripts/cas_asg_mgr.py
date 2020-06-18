#!/usr/bin/env python3

##
# Objective: Manage ASG during re-stacking operations

from optparse import OptionParser
import sys
import boto3
import pprint
import time
import datetime
from cas_ec2_mgr import CasEC2Manager

pp = pprint.PrettyPrinter(indent=4)


class CasASGManager:
    """Class that manages the ASG for the Cassandra nodes"""
    _session = None
    _client = None
    _client_asg = None
    _resource = None
    _ec2_mgr = None

    def __init__(self):
        self._session = boto3.Session(region_name="us-west-2")
        self._client = self._session.client('ec2')
        self._client_asg = self._session.client('autoscaling')
        self._resource = self._session.resource('ec2')
        self._ec2_mgr = CasEC2Manager(self._session, self._client, self._resource)
        self._pp = pprint.PrettyPrinter(indent=4)

    def get_asgs(self, account, cluster, asg_node_list):
        asgs = {}
        hosts = self._ec2_mgr.get_hosts(account, cluster, asg_node_list, True)
        for h in hosts:
            asg = h["asg"]
            nodes = []
            node = {"id": h["id"], "active_interface": h["active_interface"], "eth0": h["eth0"], "eth1": h["eth1"]}
            if asg in asgs:
                nodes = asgs[asg]

            nodes.append(node)
            asgs[asg] = nodes
        return asgs

    def increase(self, increase_asgs):
        print("Logic: increase the size of asgs if the current size is 1")
        for asg in increase_asgs:
            print("Processing %s" % asg)
            if len(increase_asgs[asg]) == 1:
                print("Increasing the capacity to 2")
                response = self._client_asg.set_desired_capacity(AutoScalingGroupName=asg, DesiredCapacity=2,
                                                                 HonorCooldown=False)
                self._pp.pprint(response)
            elif len(increase_asgs[asg]) == 2:
                print("%s autoscaling group already has capacity set to 2" % asg)

            self.wait_for_ec2s_to_init(asg, 2)

    def wait_for_ec2s_to_init(self, asg, expected_size):
        # Wait for all instances to be of expected_capacity
        while True:
            response = self._client_asg.describe_auto_scaling_groups(AutoScalingGroupNames=[asg])
            inst_arr = [x["Instances"] for x in response["AutoScalingGroups"] if x["AutoScalingGroupName"] == asg]
            asg_resp_inst = inst_arr[0]

            if len(asg_resp_inst) == expected_size:
                break
            else:
                print("%s : Waiting for the asg [%s] to have %d instances and it has %d instances" % (
                    datetime.datetime.now(), asg, expected_size, len(asg_resp_inst)))
                time.sleep(20)

        # Ensure that all the instances are InService state
        while True:
            instance_ids = [x["InstanceId"] for x in asg_resp_inst]
            response = self._client_asg.describe_auto_scaling_instances(InstanceIds=instance_ids)
            inst_not_inservice = [x for x in response["AutoScalingInstances"] if x["LifecycleState"] != "InService"]
            if len(inst_not_inservice) == 0:
                break
            else:
                print("%s : Waiting for all the asg [%s] instances to be in InService state" % (
                    datetime.datetime.now(), asg))
                time.sleep(20)

        print("%s : Waiting for all the asg [%s] instances to be initialized (~4 mins). Please be patient..." % (
              datetime.datetime.now(), asg))

        # ensure that instances are initialized
        response = self._client_asg.describe_auto_scaling_groups(AutoScalingGroupNames=[asg])
        inst_arr = [x["Instances"] for x in response["AutoScalingGroups"] if x["AutoScalingGroupName"] == asg]
        asg_resp_inst = inst_arr[0]
        instance_ids = [x["InstanceId"] for x in asg_resp_inst]
        waiter = self._client.get_waiter('instance_status_ok')
        waiter.wait(InstanceIds=instance_ids)
        print("%s : All the asg [%s] instances completed initialization" % (datetime.datetime.now(), asg))

    def decrease(self, decrease_asgs):
        print("decrease the size of asg by terminating the instance with active_interface as eth0")
        for asg in decrease_asgs:
            print("Processing %s" % asg)
            if len(decrease_asgs[asg]) > 1:
                print("Decreasing the capacity to 1")
                inst_to_terminate = [x for x in decrease_asgs[asg] if x["active_interface"] == "eth0"]
                for i in inst_to_terminate:
                    response = self._client_asg.terminate_instance_in_auto_scaling_group(InstanceId=i["id"],
                                                                                         ShouldDecrementDesiredCapacity=True)
                    self.wait_for_ec2s_to_init(asg, 1)
            elif len(decrease_asgs[asg]) == 1:
                print("%s autoscaling group already has capacity set to 1" % asg)

    def reset(self, reset_asgs):
        print("Logic: terminate the instance and wait for the new instance to initialize")
        for asg in reset_asgs:
            print("Processing %s" % asg)
            if len(reset_asgs[asg]) == 1:
                response = self._client_asg.terminate_instance_in_auto_scaling_group(InstanceId=reset_asgs[asg][0]["id"],
                                                                                     ShouldDecrementDesiredCapacity=False)
                self._pp.pprint(response)

            self.wait_for_ec2s_to_init(asg, 1)


if __name__ == "__main__":
    parser = OptionParser()

    parser.add_option("-p", "--aws_profile", dest="aws_profile", help="AWS profile")
    parser.add_option("-a", "--account", dest="account", help="Account number")
    parser.add_option("-c", "--cluster", dest="cluster", help="cluster")
    parser.add_option("-o", "--operation", dest="operation", help="operation - increase|decrease", default="increase")
    parser.add_option("-n", "--nodes", dest="nodes", help="name of the nodes", default="all")

    (options, args) = parser.parse_args(sys.argv)
    casASGMgr = CasASGManager()
    node_list = []
    if options.nodes != "all":
        node_list = options.nodes.split(",")

    asgs = casASGMgr.get_asgs(options.account, options.cluster, node_list)
    pp.pprint(asgs)
    if options.operation == "increase":
        casASGMgr.increase(asgs)
    elif options.operation == "decrease":
        casASGMgr.decrease(asgs)
    else:
        casASGMgr.reset(asgs)
