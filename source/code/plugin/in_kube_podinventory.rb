#!/usr/local/bin/ruby

module Fluent

  class Kube_PodInventory_Input < Input
    Plugin.register_input('kubepodinventory', self)

    def initialize
      super
      require 'yaml'
      require 'json'
      
      require_relative 'KubernetesApiClient'
      require_relative 'oms_common'
      require_relative 'omslog'
    end

    config_param :run_interval, :time, :default => '10m'
    config_param :tag, :string, :default => "oms.api.KubePodInventory"

    def configure (conf)
      super
    end

    def start
      if KubernetesApiClient.isValidRunningNode && @run_interval
        @finished = false
        @condition = ConditionVariable.new
        @mutex = Mutex.new
        @thread = Thread.new(&method(:run_periodic))
      else
        enumerate
      end  
    end

    def shutdown
      if KubernetesApiClient.isValidRunningNode && @run_interval
        @mutex.synchronize {
          @finished = true
          @condition.signal
        }
        @thread.join
      end 
    end

    def enumerate(podList = nil)
      time = Time.now.to_f
      if KubernetesApiClient.isValidRunningNode
        if podList.nil?
          podInventory = JSON.parse(KubernetesApiClient.getKubeResourceInfo('pods').body)
        else
          podInventory = podList
        end    
        podInventory['items'].each do |items|
          record = {}
          begin 
            record['Name'] = items['metadata']['name']
            record['PodUid'] = items['metadata']['uid']
            record['PodLabel'] = items['metadata']['labels']
            record['Namespace'] = items['metadata']['namespace']
            record['PodCreationTimeStamp'] = items['metadata']['creationTimestamp']
            record['PodStatus'] = items['status']['phase']
            record['PodIp'] =items['status']['podIP']
            record['Computer'] = items['spec']['nodeName']
            record['ClusterName'] = KubernetesApiClient.getClusterName
            router.emit(@tag, time, record) if record
          rescue  => errorStr
            $log.warn line.dump, error: errorStr.to_s
            $log.debug_backtrace(e.backtrace)
          end
        end
      else
        record = {}
        record['Name'] = ""
        record['PodUid'] = ""
        record['PodLabel'] = ""
        record['Namespace'] = ""
        record['PodCreationTimeStamp'] = ""
        record['PodStatus'] = ""
        record['PodIp'] = ""
        record['Computer'] = ""
        record['ClusterName'] = ""
        router.emit(@tag, time, record)  
      end  
    end

    def run_periodic
      @mutex.lock
      done = @finished
      until done
        @condition.wait(@mutex, @run_interval)
        done = @finished
        @mutex.unlock
        if !done
          enumerate
        end
        @mutex.lock
      end
      @mutex.unlock
    end
    
  end # Kube_Pod_Input

end # module

