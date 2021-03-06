#!/usr/bin/env rspec

load File.join(File.dirname(__FILE__), "../", "../", "../", "pxp-module-puppet")

describe "pxp-module-puppet" do

  let(:default_params) {
    {"env" => [], "flags" => []}
  }

  let(:default_config) {
    {"puppet_bin" => "puppet"}
  }

  describe "check_config_print" do
    it "returns the result of configprint" do
      cli_str = "puppet agent --configprint value"
      expect(Puppet::Util::Execution).to receive(:execute).with(cli_str).and_return("value\n")
      expect(check_config_print("value", default_config)).to be == "value"
    end
  end

  describe "running?" do
    it "checks if the agent_catalog_run_lockfile exists" do
      expect_any_instance_of(Object).to receive(:check_config_print).with(
        "agent_catalog_run_lockfile", default_config).and_return(
        "agent_catalog_run_lockfile")
      expect(File).to receive(:exist?).with("agent_catalog_run_lockfile")
      running?(default_config)
    end
  end

  describe "disabled?" do
    it "checks if the agent_disabled_lockfile exists" do
      expect_any_instance_of(Object).to receive(:check_config_print).with(
        "agent_disabled_lockfile", default_config).and_return(
        "agent_disabled_lockfile")
      expect(File).to receive(:exist?).with("agent_disabled_lockfile")
      disabled?(default_config)
    end
  end

  describe "make_command_string"do
    it "should correctly prepend the env variables" do
      params = default_params
      params["env"] = ["FOO=bar", "BAR=foo"]
      expect(make_command_string(default_config, params)).to be ==
        "FOO=bar BAR=foo puppet agent --no-usecacheonfailure --no-splay --show_diff --no-daemonize --onetime --verbose  > /dev/null 2>&1"
    end

    it "should correctly append any flags" do
      params = default_params
      params["flags"] = ["--noop", "--foo=bar"]
      expect(make_command_string(default_config, params)).to be ==
        "puppet agent --no-usecacheonfailure --no-splay --show_diff --no-daemonize --onetime --verbose --noop --foo=bar > /dev/null 2>&1"
    end

    it "should correctly join both flags and env variables" do
      params = default_params
      params["env"] = ["FOO=bar", "BAR=foo"]
      params["flags"] = ["--noop", "--foo=bar"]

      expect(make_command_string(default_config, params)).to be ==
        "FOO=bar BAR=foo puppet agent --no-usecacheonfailure --no-splay --show_diff --no-daemonize --onetime --verbose --noop --foo=bar > /dev/null 2>&1"
    end

    it "uses the correct 'dev/null' on Windows" do
      allow_any_instance_of(Object).to receive(:is_win?).and_return("true")
      expect(make_command_string(default_config, default_params)).to be ==
        "puppet agent --no-usecacheonfailure --no-splay --show_diff --no-daemonize --onetime --verbose  > nul 2>&1"
    end
  end

  describe "get_result_from_report" do
    it "doesn't process the last_run_report if exitcode isn't 0" do
      expect(get_result_from_report(-1, default_config, "a test error occurred")).to be ==
          {"kind"             => "unknown",
           "time"             => "unknown",
           "transaction_uuid" => "unknown",
           "environment"      => "unknown",
           "status"           => "unknown",
           "error"            => "a test error occurred",
           "exitcode"         => -1}
    end

    it "doesn't process the last_run_report if the file doens't exist" do
      allow(File).to receive(:exist?).and_return(false)
      allow_any_instance_of(Object).to receive(:check_config_print).and_return("/opt/puppetlabs/puppet/cache/state/")
      expect(get_result_from_report(0, default_config)).to be ==
          {"kind"             => "unknown",
           "time"             => "unknown",
           "transaction_uuid" => "unknown",
           "environment"      => "unknown",
           "status"           => "unknown",
           "error"            => "/opt/puppetlabs/puppet/cache/state/last_run_report.yaml doesn't exist",
           "exitcode"         => 0}
    end

    it "doesn't process the last_run_report if the file isn't valid yaml" do
      allow(File).to receive(:exist?).and_return(true)
      allow_any_instance_of(Object).to receive(:check_config_print).and_return("/opt/puppetlabs/puppet/cache/state/")
      allow(YAML).to receive(:load_file).and_raise("error")
      expect(get_result_from_report(0, default_config)).to be ==
          {"kind"             => "unknown",
           "time"             => "unknown",
           "transaction_uuid" => "unknown",
           "environment"      => "unknown",
           "status"           => "unknown",
           "error"            => "/opt/puppetlabs/puppet/cache/state/last_run_report.yaml isn't valid yaml",
           "exitcode"         => 0}
    end

    it "correctly processes the last_run_report" do
      last_run_report = double(:last_run_report)
      allow(last_run_report).to receive(:kind).and_return("apply")
      allow(last_run_report).to receive(:time).and_return("2015-09-07 11:09:49.973632164 +00:00")
      allow(last_run_report).to receive(:transaction_uuid).and_return("ac59acbe-6a0f-49c9-8ece-f781a689fda9")
      allow(last_run_report).to receive(:environment).and_return("production")
      allow(last_run_report).to receive(:status).and_return("changed")

      allow(File).to receive(:exist?).and_return(true)
      allow_any_instance_of(Object).to receive(:check_config_print).and_return("/opt/puppetlabs/puppet/cache/state/")
      allow(YAML).to receive(:load_file).and_return(last_run_report)
      expect(get_result_from_report(0, default_config)).to be ==
          {"kind"             => "apply",
           "time"             => "2015-09-07 11:09:49.973632164 +00:00",
           "transaction_uuid" => "ac59acbe-6a0f-49c9-8ece-f781a689fda9",
           "environment"      => "production",
           "status"           => "changed",
           "error"            => "",
           "exitcode"         => 0}
    end
  end

  describe "start_run" do
    let(:runoutcome) {
      double(:runoutcome)
    }

    it "populates output when it terminated normally" do
      allow(Puppet::Util::Execution).to receive(:execute).and_return(runoutcome)
      allow(runoutcome).to receive(:exitstatus).and_return(0)
      allow_any_instance_of(Object).to receive(:get_result_from_report).with(0, default_config)
      start_run(default_config, default_params)
    end

    it "populates output when it terminated with a non 0 code" do
      allow(Puppet::Util::Execution).to receive(:execute).and_return(runoutcome)
      allow(runoutcome).to receive(:exitstatus).and_return(1)
      allow_any_instance_of(Object).to receive(:get_result_from_report).with(1, default_config,
                                                                        "Puppet agent exited with a non 0 exitcode")
      start_run(default_config, default_params)
    end

    it "populates output when it couldn't start" do
      allow(Puppet::Util::Execution).to receive(:execute).and_return(nil)
      allow_any_instance_of(Object).to receive(:get_result_from_report).with(-1, default_config,
                                                                        "Failed to start Puppet agent")
      start_run(default_config, default_params)
    end
  end

  describe "action_metadata" do
    it "has the correct metadata" do
      expect(metadata).to be == {
        :description => "PXP Puppet module",
        :actions => [
          { :name        => "run",
            :description => "Start a Puppet run",
            :input       => {
              :type      => "object",
              :properties => {
                :env => {
                  :type => "array",
                },
                :flags => {
                  :type => "array",
                }
              },
              :required => [:env, :flags]
            },
            :output => {
              :type => "object",
              :properties => {
                :kind => {
                  :type => "string"
                },
                :time => {
                  :type => "string"
                },
                :transaction_uuid => {
                  :type => "string"
                },
                :environment => {
                  :type => "string"
                },
                :status => {
                  :type => "string"
                },
                :error => {
                  :type => "string"
                },
                :exitcode => {
                  :type => "number"
                }
              },
              :required => [:kind, :time, :transaction_uuid, :environment, :status,
                            :error, :exitcode]
            }
          }
        ],
        :configuration => {
          :type => "object",
          :properties => {
            :puppet_bin => {
              :type => "string"
            }
          }
        }
      }
    end
  end

  describe "run" do
    it "fails when puppet_bin isn't set" do
        expect(run({"config" => {}, "params" => default_params})["error"]).to be ==
          "puppet_bin configuration value not set"
    end

    it "fails when puppet_bin doesn't exist" do
      allow(File).to receive(:exist?).and_return(false)
        expect(run({"config" => default_config, "params" => default_params})["error"]).to be ==
          "Puppet executable 'puppet' does not exist"
    end

    it "fails if puppet is already running" do
      allow(File).to receive(:exist?).and_return(true)
      allow_any_instance_of(Object).to receive(:running?).and_return(true)
      expect(run({"config" => default_config, "params" => default_params})["error"]).to be ==
          "Puppet agent is already performing a run"
    end

    it "fails if puppet is disabled" do
      allow(File).to receive(:exist?).and_return(true)
      allow_any_instance_of(Object).to receive(:running?).and_return(false)
      allow_any_instance_of(Object).to receive(:disabled?).and_return(true)
      expect(run({"config" => default_config, "params" => default_params})["error"]).to be ==
          "Puppet agent is disabled"
    end

    it "fails when invalid json is passed" do
      # JSON is parsed when the action is invoked. Any invalid json will call run
      # with nil
      expect(run(nil)["error"]).to be ==
          "Invalid json parsed on STDIN. Cannot start run action"
    end

    it "starts the run" do
      allow(File).to receive(:exist?).and_return(true)
      allow_any_instance_of(Object).to receive(:running?).and_return(false)
      allow_any_instance_of(Object).to receive(:disabled?).and_return(false)
      expect_any_instance_of(Object).to receive(:start_run)
      run({"config" => default_config, "params" => default_params})
    end
  end
end
