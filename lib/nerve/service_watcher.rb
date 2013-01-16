module Nerve
  class ServiceWatcher

    include Logging

    def initialize(opts={})
      log.debug "creating service watcher object"
      %w{port zk_path instance_id name}.each do |required|
        raise ArgumentError, "you need to specify required argument #{required}" unless opts[required]
        instance_variable_set("@#{required}",opts['required'])
      end
      @host = opts['host'] ? opts['host'] : '0.0.0.0'
      # TODO(mkr): maybe take these as inputs
      @threshold = 2
      opts['checks'] ||= {}
      opts['checks'].each do |type,params|
        service_check_class_name = type.split("_").map(&:capitalize).join
        service_check_class_name << "ServiceCheck"
        begin
          service_check_class = ServiceCheck.const_get(service_check_class_name)
        rescue
          raise ArgumentError, "invalid service check: #{type}"
        end
      end
    end

    def run()
      log.info "watching service #{@name}"
      @zk = ZKHelper.new(@zk_path)
      @zk.delete(@instance_id)
      ring_buffer = RingBuffer(@threshold)
      @threshold.times { ring_buffer.push false }

      unless defined?(EXIT)
        begin
          @zk.ping?
          ring_buffer.push check?
          if ring_buffer.include?(false)
            @zk.delete(@instance_id)
          else
            @zk.ensure_ephemeral_node(@instance_id)
          end
        rescue Object => o
          log.error "hit an error, setting exit: "
          log.error o.inspect
          log.error o.backtrace
          self.class.const_set(:EXIT,true)
        end
      end
    end

    def check?
      @service_checks.each do |check|
        return false unless check.check?
      end
      return true
    end

  end
end
