#!/usr/local/bin/ruby

class KubernetesApiClient
    
        require 'json'
        require 'logger'
        require 'net/http'
        require 'net/https'
        require 'uri'
    
        require_relative 'oms_common'
    
        @@ApiVersion = "v1"    
        @@CaFile = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
        @@ClusterName = nil
        @@IsNodeMaster = nil
        @@KubeSystemNamespace = "kube-system"
        @LogPath = "/var/opt/microsoft/omsagent/log/kubernetes_client_log.txt"
        @Log = Logger.new(@LogPath, 'weekly')
        @@TokenFileName = "/var/run/secrets/kubernetes.io/serviceaccount/token"
        @@TokenStr = nil
    
        def initialize
        end
    
        class << self
            def getKubeResourceInfo(resource)    
                headers = {}
                response = ""
                @Log.info 'Getting Kube resource'
                @Log.info resource
                begin
                    resourceUri = getResourceUri(resource)
                    if !resourceUri.nil?
                        uri = URI.parse(resourceUri)
                        http = Net::HTTP.new(uri.host, uri.port)
                        http.use_ssl = true
                        if !File.exist?(@@CaFile)
                            raise "#{@@CaFile} doesnt exist"
                        else
                            http.ca_file = @@CaFile if File.exist?(@@CaFile)
                        end
                        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    
                        kubeApiRequest = Net::HTTP::Get.new(uri.request_uri)
                        kubeApiRequest['Authorization'] = "Bearer " + getTokenStr
                        response = http.request(kubeApiRequest)
                    end    
                rescue => error
                    @Log.warn("kubernetes api request failed: #{error}") 
                end       
                return response
            end
    
            def getTokenStr
                return @@TokenStr if !@@TokenStr.nil?
                begin
                    if File.exist?(@@TokenFileName) && File.readable?(@@TokenFileName)
                        @@TokenStr = File.read(@@TokenFileName).strip
                        return @@TokenStr
                    else
                       @Log.warn("Unable to read token string from #{@@TokenFileName}: #{error}")
                       return nil
                    end
                end
            end
            
            def getResourceUri(resource)
                begin
                    if ENV['KUBERNETES_SERVICE_HOST'] && ENV['KUBERNETES_PORT_443_TCP_PORT']
                        return "https://#{ENV['KUBERNETES_SERVICE_HOST']}:#{ENV['KUBERNETES_PORT_443_TCP_PORT']}/api/" + @@ApiVersion + "/" + resource
                    else
                        @Log.warn ("Kubernetes environment variable not set KUBERNETES_SERVICE_HOST: #{ENV['KUBERNETES_SERVICE_HOST']} KUBERNETES_PORT_443_TCP_PORT: #{ENV['KUBERNETES_PORT_443_TCP_PORT']}. Unable to form resourceUri")
                        return nil
                    end    
                end
            end
    
            def getClusterName
                return @@ClusterName if !@@ClusterName.nil?
                begin
                    kubesystemResourceUri = "namespaces/" + @@KubeSystemNamespace + "/pods"
                    podInfo = JSON.parse(getKubeResourceInfo(kubesystemResourceUri).body)
                    podInfo['items'].each do |items|
                        if items['metadata']['name'].include? "kube-controller-manager"
                           items['spec']['containers'][0]['command'].each do |command|
                               if command.include? "--cluster-name"
                                   @@ClusterName = command.split('=')[1]
                               end    
                           end
                        end
                    end
                    @@ClusterName = "None"
                rescue => error
                    @Log.warn("cluster name request failed: #{error}")    
                end
                return @@ClusterName    
            end
    
            def isNodeMaster
                return @@IsNodeMaster if !@@IsNodeMaster.nil?
                @@IsNodeMaster = false
                begin
                    allNodesInfo = JSON.parse(getKubeResourceInfo('nodes').body)
                    if !allNodesInfo.nil? && !allNodesInfo.empty?
                        thisNodeName = OMS::Common.get_hostname
                        allNodesInfo['items'].each do |item|
                            if item['metadata']['name'].casecmp(thisNodeName) == 0
                                if item['metadata']['labels']["kubernetes.io/role"].to_s.include?("master") && item['metadata']['labels']["kubernetes.io/hostname"].to_s.split('-').last == '0'
                                    @@IsNodeMaster = true                                    
                                end    
                                break
                            end
                        end  
                    end         
                rescue => error
                    @Log.warn("node role request failed: #{error}")    
                end
                if(@@IsNodeMaster == true)
                    @Log.info("Electing current node to talk to k8 api")
                else
                    @Log.info("Not Electing current node to talk to k8 api")
                end
                return @@IsNodeMaster
            end    
            
            # returns an arry of pods (json)
            def getPods(namespace)
                @@Pods= []
                begin
                    kubesystemResourceUri = "namespaces/" + namespace + "/pods"
                    podInfo = JSON.parse(getKubeResourceInfo(kubesystemResourceUri).body)
                    podInfo['items'].each do |items|
                        @@Pods.push items
                    end
                rescue => error
                    @Log.warn("List pods request failed: #{error}")    
                end
                return @@Pods
            end
    
            def getContainerLogs(namespace, pod, container, showTimeStamp)
                @@ContainerLogs = ""
                begin
                    kubesystemResourceUri = "namespaces/" + namespace + "/pods/" + pod + "/log" + "?container=" + container
                    if showTimeStamp 
                        kubesystemResourceUri += "&timestamps=true"
                    end
                    @@ContainerLogs = getKubeResourceInfo(kubesystemResourceUri).body
                rescue => error
                    @Log.warn("Pod logs request failed: #{error}")    
                end
                return @@ContainerLogs  
            end
    
            def getContainerLogsSinceTime(namespace, pod, container, since, showTimeStamp)
                @@ContainerLogs = ""
                begin
                    # HTML URL Encoding
                    since.gsub! ":", "%3A"
                    since.gsub! ".", "%2E"
                    since.gsub! "+", "%2B"
                    kubesystemResourceUri = "namespaces/" + namespace + "/pods/" + pod + "/log" + "?container=" + container + "&sinceTime=" + since
                    if showTimeStamp 
                        kubesystemResourceUri += "&timestamps=true"
                    end
                    @@ContainerLogs = getKubeResourceInfo(kubesystemResourceUri).body
                rescue => error
                    @Log.warn("Pod logs request failed: #{error}")    
                end
                return @@ContainerLogs  
            end
        end    
    end   
    