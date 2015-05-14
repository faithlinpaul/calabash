describe Calabash::IOS::Device do
  it 'should inherit from Calabash::Device' do
    expect(Calabash::IOS::Device.ancestors).to include(Calabash::Device)
  end

  let(:identifier) {'my-identifier'}
  let(:server) {Calabash::IOS::Server.new(URI.parse('http://localhost:37265'))}
  let(:device) {Calabash::IOS::Device.new(identifier, server)}

  let(:dummy_device_class) {Class.new(Calabash::IOS::Device) {def initialize; @logger = Calabash::Logger.new; end}}
  let(:dummy_device) {dummy_device_class.new}
  let(:dummy_http_class) {Class.new(Calabash::HTTP::RetriableClient) {def initialize; end}}
  let(:dummy_http) {dummy_http_class.new}

  before(:each) do
    allow(dummy_device).to receive(:http_client).and_return(dummy_http)
    allow_any_instance_of(Calabash::Application).to receive(:ensure_application_path)
  end

  describe '.default_simulator_identifier' do
    describe 'when DEVICE_IDENTIFIER is non-nil' do
      it 'raises an error if the simulator cannot be found' do
        stub_const('Calabash::Environment::DEVICE_IDENTIFIER', 'some identifier')
        expect(Calabash::IOS::Device).to receive(:fetch_matching_simulator).and_return(nil)
        expect {
          Calabash::IOS::Device.default_simulator_identifier
        }.to raise_error
      end

      it 'returns the instruments identifier of the simulator' do
        stub_const('Calabash::Environment::DEVICE_IDENTIFIER', 'some identifier')
        sim = RunLoop::Device.new('fake', '8.0', 'some identifier')
        expect(Calabash::IOS::Device).to receive(:fetch_matching_simulator).and_return(sim)
        expect(sim).to receive(:instruments_identifier).and_return 'fake (8.0 Simulator)'
        expect(Calabash::IOS::Device.default_simulator_identifier).to be == 'fake (8.0 Simulator)'
      end
    end

    it 'when DEVICE_IDENTIFIER is nil, returns the default simulator' do
      stub_const('Calabash::Environment::DEVICE_IDENTIFIER', nil)
      expect(RunLoop::Core).to receive(:default_simulator).and_return('default sim')
      expect(Calabash::IOS::Device.default_simulator_identifier).to be == 'default sim'
    end
  end

  describe '.default_physical_device_identifier' do
    describe 'when DEVICE_IDENTIFIER is non-nil' do
      it 'raises an error if the device cannot be found' do
        stub_const('Calabash::Environment::DEVICE_IDENTIFIER', 'some identifier')
        expect(Calabash::IOS::Device).to receive(:fetch_matching_physical_device).and_return(nil)
        expect {
          Calabash::IOS::Device.default_physical_device_identifier
        }.to raise_error
      end

      it 'returns the instruments identifier of the device' do
        stub_const('Calabash::Environment::DEVICE_IDENTIFIER', 'some identifier')
        p_device = RunLoop::Device.new('fake', '8.0', 'some identifier')
        expect(p_device).to receive(:physical_device?).at_least(:once).and_return(true)
        expect(Calabash::IOS::Device).to receive(:fetch_matching_physical_device).and_return(p_device)
        expect(Calabash::IOS::Device.default_physical_device_identifier).to be == p_device.instruments_identifier
      end
    end

    describe 'when DEVICE_IDENTIFIER is nil' do
      describe 'raises an error when' do
        it 'there are no connected devices' do
          stub_const('Calabash::Environment::DEVICE_IDENTIFIER', nil)
          allow_any_instance_of(RunLoop::XCTools).to receive(:instruments).with(:devices).and_return([])
          expect {
            Calabash::IOS::Device.default_physical_device_identifier
          }.to raise_error
        end

        it 'there is more than one connected device' do
          stub_const('Calabash::Environment::DEVICE_IDENTIFIER', nil)
          allow_any_instance_of(RunLoop::XCTools).to receive(:instruments).with(:devices).and_return([1, 2])
          expect {
            Calabash::IOS::Device.default_physical_device_identifier
          }.to raise_error
        end
      end

      it 'returns the device identifier of the connected device' do
        stub_const('Calabash::Environment::DEVICE_IDENTIFIER', nil)
        p_device = RunLoop::Device.new('fake', '8.0', 'some identifier')
        allow_any_instance_of(RunLoop::XCTools).to receive(:instruments).with(:devices).and_return([p_device])
        expect(p_device).to receive(:physical_device?).at_least(:once).and_return(true)
        expect(Calabash::IOS::Device.default_physical_device_identifier).to be == p_device.instruments_identifier
      end
    end
  end

  describe '.default_identifier_for_application' do
    let(:app) { Calabash::IOS::Application.new(IOSResources.instance.app_bundle_path) }
    it 'returns simulator identifier for .app' do
      expect(app).to receive(:simulator_bundle?).and_return(true)
      expect(Calabash::IOS::Device).to receive(:default_simulator_identifier).and_return('sim id')
      expect(Calabash::IOS::Device.default_identifier_for_application(app)).to be == 'sim id'
    end

    it 'returns device identifier for .ipa' do
      expect(app).to receive(:simulator_bundle?).and_return(false)
      expect(app).to receive(:device_binary?).and_return(true)
      expect(Calabash::IOS::Device).to receive(:default_physical_device_identifier).and_return('device id')
      expect(Calabash::IOS::Device.default_identifier_for_application(app)).to be == 'device id'
    end

    it 'raises an error if the application is not an .app or .ipa' do
      expect(app).to receive(:simulator_bundle?).and_return(false)
      expect(app).to receive(:device_binary?).and_return(false)
      expect {
        Calabash::IOS::Device.default_identifier_for_application(app)
      }.to raise_error
    end
  end

  describe '.expect_compatible_server_endpoint' do
    it 'server is not localhost do nothing' do
      expect(server).to receive(:localhost?).and_return(false)
      expect {
        Calabash::IOS::Device.send(:expect_compatible_server_endpoint, 'my id', server)
      }.not_to raise_error
    end

    describe 'server is localhost' do
      it 'raises an error if identifier does not resolve to a simulator' do
        expect(server).to receive(:localhost?).and_return(true)
        expect(Calabash::IOS::Device).to receive(:fetch_matching_simulator).and_return(nil)
        expect {
          Calabash::IOS::Device.send(:expect_compatible_server_endpoint, 'my id', server)
        }.to raise_error
      end

      it 'does nothing if the identifier resolves to a simulator' do
        expect(server).to receive(:localhost?).and_return(true)
        expect(Calabash::IOS::Device).to receive(:fetch_matching_simulator).and_return('a')
        expect {
          Calabash::IOS::Device.send(:expect_compatible_server_endpoint, 'my id', server)
        }.not_to raise_error
      end
    end
  end

  describe 'instance methods requiring expect_compatible_server_endpoint' do

    before do
      allow(Calabash::IOS::Device).to receive(:expect_compatible_server_endpoint).and_return(true)
    end

    describe 'abstract methods' do
      it '#install_app_on_physical_device' do
        expect {
          device.install_app_on_physical_device('app', 'device id')
        }.to raise_error Calabash::AbstractMethodError
      end

      it '#ensure_app_installed_on_physical_device' do
        expect {
          device.ensure_app_installed_on_physical_device('app', 'device id')
        }.to raise_error Calabash::AbstractMethodError
      end
    end

    describe '#start_app' do
      let(:app) { Calabash::IOS::Application.new(IOSResources.instance.app_bundle_path) }
      let(:options) { {} }

      it 'raises an error if app is not an .ipa or .app' do
        expect(app).to receive(:simulator_bundle?).and_return false
        expect(app).to receive(:device_binary?).and_return false
        expect {
          device.start_app(app)
        }.to raise_error
      end

      it 'calls start_app_on_simulator when app is a simulator bundle' do
        expect(app).to receive(:simulator_bundle?).and_return true
        expect(device).to receive(:start_app_on_simulator).with(app, options).and_return true

        expect(device.start_app(app, options)).to be_truthy
      end

      it 'calls start_app_on_physical_device when app is a device binary' do
        expect(app).to receive(:simulator_bundle?).and_return false
        expect(app).to receive(:device_binary?).and_return true
        expect(device).to receive(:start_app_on_physical_device).with(app, options).and_return true

        expect(device.start_app(app, options)).to be_truthy
      end
    end

    describe '#test_server_responding?' do
      let(:dummy_http_response_class) {Class.new {def status; end}}
      let(:dummy_http_response) {dummy_http_response_class.new}

      it 'should return false when a Calabash:HTTP::Error is raised' do
        allow(dummy_device.http_client).to receive(:get).and_raise(Calabash::HTTP::Error)

        expect(dummy_device.test_server_responding?).to be == false
      end

      it 'should return false when the status code is not 200' do
        allow(dummy_http_response).to receive(:status).and_return('100')
        allow(dummy_device.http_client).to receive(:get).and_return(dummy_http_response)

        expect(dummy_device.test_server_responding?).to be == false
      end

      it 'should return true when ping responds pong' do
        allow(dummy_http_response).to receive(:status).and_return('200')
        allow(dummy_device.http_client).to receive(:get).and_return(dummy_http_response)

        expect(dummy_device.test_server_responding?).to be == true
      end
    end

    describe '#stop_app' do
      it 'does nothing if server is not responding' do
        expect(device).to receive(:test_server_responding?).and_return(false)
        expect(device.stop_app).to be_truthy
      end

      it "calls the server 'exit' route" do
        expect(device).to receive(:test_server_responding?).and_return(true)
        params = device.send(:default_stop_app_parameters)
        request = Calabash::HTTP::Request.new('exit', params)
        expect(device).to receive(:request_factory).and_return(request)
        expect(device.http_client).to receive(:get).with(request).and_return([])
        expect(device.stop_app).to be_truthy
      end

      it 'raises an exception if server cannot be reached' do
        expect(device).to receive(:test_server_responding?).and_return(true)
        expect(device.http_client).to receive(:get).and_raise(Calabash::HTTP::Error)
        expect { device.stop_app }.to raise_error
      end
    end

    describe '#screenshot' do
      it 'raise an exception if the server cannot be reached' do
        expect(device.http_client).to receive(:get).and_raise(Calabash::HTTP::Error)
        expect { device.screenshot('path') }.to raise_error
      end

      it 'writes screenshot to a file' do
        path = File.join(Dir.mktmpdir, 'screenshot.png')
        expect(Calabash::Screenshot).to receive(:obtain_screenshot_path!).and_return(path)
        request = Calabash::HTTP::Request.new('exit', {path: path})
        expect(device).to receive(:request_factory).and_return(request)
        data = 'I am the screenshot!'
        expect(device.http_client).to receive(:get).with(request).and_return(data)
        expect(device.screenshot(path)).to be == path
        expect(File.read(path)).to be == data
      end
    end

    describe '#install_app' do
      let(:run_loop_device) { RunLoop::Device.new('denis', '8.3', 'udid') }
      let(:app) { Calabash::IOS::Application.new(IOSResources.instance.app_bundle_path) }

      it 'raises an error when application is not an .ipa or .app' do
        expect(app).to receive(:simulator_bundle?).at_least(:once).and_return false
        expect(app).to receive(:device_binary?).at_least(:once).and_return false

        expect {
          device.install_app(app)
        }.to raise_error
      end

      describe 'on a simulator' do
        it 'raises error when no matching simulator can be found' do
          expect(app).to receive(:simulator_bundle?).at_least(:once).and_return true
          expect(Calabash::IOS::Device).to receive(:fetch_matching_simulator).and_return nil

          expect {
            device.install_app(app)
          }.to raise_error
        end

        it 'calls install_app_on_simulator' do
          expect(app).to receive(:simulator_bundle?).at_least(:once).and_return true
          expect(Calabash::IOS::Device).to receive(:fetch_matching_simulator).and_return run_loop_device
          expect(device).to receive(:install_app_on_simulator).with(app, run_loop_device).and_return true

          expect(device.install_app(app)).to be_truthy
          expect(device.instance_variable_get(:@run_loop_device)).to be == run_loop_device
        end
      end

      describe 'on a device' do
        it 'raises an error when no matching device can be found' do
          expect(app).to receive(:simulator_bundle?).at_least(:once).and_return false
          expect(app).to receive(:device_binary?).at_least(:once).and_return true
          expect(Calabash::IOS::Device).to receive(:fetch_matching_physical_device).and_return nil

          expect {
            device.install_app(app)
          }.to raise_error
        end

        it 'calls install_app_on_device' do
          expect(app).to receive(:simulator_bundle?).at_least(:once).and_return false
          expect(app).to receive(:device_binary?).at_least(:once).and_return true
          expect(Calabash::IOS::Device).to receive(:fetch_matching_physical_device).and_return run_loop_device
          expect(device).to receive(:install_app_on_physical_device).with(app, run_loop_device.udid).and_return true

          expect(device.install_app(app)).to be_truthy
          expect(device.instance_variable_get(:@run_loop_device)).to be == run_loop_device
        end
      end
    end

    describe '#ensure_app_installed' do
      let(:run_loop_device) { RunLoop::Device.new('denis', '8.3', 'udid') }
      let(:app) { Calabash::IOS::Application.new(IOSResources.instance.app_bundle_path) }

      it 'raises an error when application is not an .ipa or .app' do
        expect(app).to receive(:simulator_bundle?).at_least(:once).and_return false
        expect(app).to receive(:device_binary?).at_least(:once).and_return false

        expect {
          device.ensure_app_installed(app)
        }.to raise_error
      end

      describe 'on a simulator' do
        it 'raises error when no matching simulator can be found' do
          expect(app).to receive(:simulator_bundle?).at_least(:once).and_return true
          expect(Calabash::IOS::Device).to receive(:fetch_matching_simulator).and_return nil

          expect {
            device.ensure_app_installed(app)
          }.to raise_error
        end

        let(:dummy_bridge) do
          class Calabash::DummyBridge
            def app_is_installed?

            end
          end
          Calabash::DummyBridge.new
        end

        it 'does nothing if app is already installed' do
          expect(app).to receive(:simulator_bundle?).at_least(:once).and_return true
          expect(Calabash::IOS::Device).to receive(:fetch_matching_simulator).and_return run_loop_device
          expect(device).to receive(:run_loop_bridge).and_return(dummy_bridge)
          expect(dummy_bridge).to receive(:app_is_installed?).and_return true

          expect(device.ensure_app_installed(app)).to be_truthy
          expect(device.instance_variable_get(:@run_loop_device)).to be == run_loop_device
        end

        it 'calls install_app_on_simulator if the app is not installed' do
          expect(app).to receive(:simulator_bundle?).at_least(:once).and_return true
          expect(Calabash::IOS::Device).to receive(:fetch_matching_simulator).and_return run_loop_device
          expect(device).to receive(:run_loop_bridge).and_return(dummy_bridge)
          expect(dummy_bridge).to receive(:app_is_installed?).and_return false
          expect(device).to receive(:install_app_on_simulator).with(app, run_loop_device, dummy_bridge).and_return true

          expect(device.ensure_app_installed(app)).to be_truthy
          expect(device.instance_variable_get(:@run_loop_device)).to be == run_loop_device
        end

        describe 'on a device' do
          it 'raises an error when no matching device can be found' do
            expect(app).to receive(:simulator_bundle?).at_least(:once).and_return false
            expect(app).to receive(:device_binary?).at_least(:once).and_return true
            expect(Calabash::IOS::Device).to receive(:fetch_matching_physical_device).and_return nil

            expect {
              device.ensure_app_installed(app)
            }.to raise_error
          end

          it 'calls install_app_on_device' do
            expect(app).to receive(:simulator_bundle?).at_least(:once).and_return false
            expect(app).to receive(:device_binary?).at_least(:once).and_return true
            expect(Calabash::IOS::Device).to receive(:fetch_matching_physical_device).and_return run_loop_device
            expect(device).to receive(:ensure_app_installed_on_physical_device).with(app, run_loop_device.udid).and_return true

            expect(device.ensure_app_installed(app)).to be_truthy
            expect(device.instance_variable_get(:@run_loop_device)).to be == run_loop_device
          end
        end
      end
    end

    describe '#install_app_on_simulator' do
      let(:app) { Calabash::IOS::Application.new(IOSResources.instance.app_bundle_path) }
      let(:run_loop_device) { RunLoop::Device.new('denis', '8.3', 'udid') }
      let(:dummy_bridge) do
        class Calabash::DummyBridge
          def uninstall; ; end
          def install; ; end
        end
        Calabash::DummyBridge.new
      end

      it 'uninstalls and then installs' do
        expect(dummy_bridge).to receive(:uninstall).and_return true
        expect(dummy_bridge).to receive(:install).and_return true

        expect(device.send(:install_app_on_simulator, app, run_loop_device, dummy_bridge)).to be_truthy
      end

      it 'creates a new bridge if one is not provided' do
        expect(dummy_bridge).to receive(:uninstall).and_return true
        expect(dummy_bridge).to receive(:install).and_return true
        expect(device).to receive(:run_loop_bridge).with(run_loop_device, app).and_return dummy_bridge

        expect(device.send(:install_app_on_simulator, app, run_loop_device)).to be_truthy
      end

      describe 'raises errors when' do
        it 'cannot create a new RunLoop::Simctl::Bridge' do
          expect(device).to receive(:run_loop_bridge).with(run_loop_device, app).and_raise

          expect {
            device.send(:install_app_on_simulator, app, run_loop_device)
          }.to raise_error
        end

        it 'calls bridge.uninstall and an exception is raised' do
          expect(dummy_bridge).to receive(:uninstall).and_raise

          expect {
            device.send(:install_app_on_simulator, app, run_loop_device, dummy_bridge)
          }.to raise_error
        end

        it 'calls bridge.install and an exception is raised' do
          expect(dummy_bridge).to receive(:uninstall).and_return true
          expect(dummy_bridge).to receive(:install).and_raise

          expect {
            device.send(:install_app_on_simulator, app, run_loop_device, dummy_bridge)
          }.to raise_error
        end
      end
    end

    describe '#start_app_on_simulator' do
      let(:app) { Calabash::IOS::Application.new(IOSResources.instance.app_bundle_path) }
      let(:run_loop_device) { RunLoop::Device.new('denis', '8.3', 'udid') }
      let(:dummy_bridge) do
        class Calabash::DummyBridge
        end
        Calabash::DummyBridge.new
      end
      it 'raises an error if no matching simulator is found' do
        expect(Calabash::IOS::Device).to receive(:fetch_matching_simulator).and_return nil

        expect {
          device.send(:start_app_on_simulator, app, {})
        }.to raise_error
      end

      it 'starts the app' do
        expect(Calabash::IOS::Device).to receive(:fetch_matching_simulator).and_return run_loop_device
        expect(device).to receive(:expect_valid_simulator_state_for_starting).with(app, run_loop_device).and_return true
        expect(device).to receive(:start_app_with_device_and_options).with(app, run_loop_device, {}).and_return true
        expect(device).to receive(:wait_for_server_to_start).and_return true

        expect(device.send(:start_app_on_simulator, app, {})).to be_truthy
      end
    end

    describe '#start_app_on_device' do
      let(:app) { Calabash::IOS::Application.new(IOSResources.instance.app_bundle_path) }
      let(:run_loop_device) { RunLoop::Device.new('denis', '8.3', 'udid') }

      it 'raises an error if no matching device is found' do
        expect(Calabash::IOS::Device).to receive(:fetch_matching_physical_device).and_return nil

        expect {
          device.send(:start_app_on_physical_device, app, {})
        }.to raise_error
      end

      it 'starts the app' do
        expect(Calabash::IOS::Device).to receive(:fetch_matching_physical_device).and_return run_loop_device
        expect(device).to receive(:start_app_with_device_and_options).with(app, run_loop_device, {}).and_return true
        expect(device).to receive(:wait_for_server_to_start).and_return true

        expect(device.send(:start_app_on_physical_device, app, {})).to be_truthy
      end
    end

    it '#start_app_with_device_and_options' do
      app = Calabash::IOS::Application.new(IOSResources.instance.app_bundle_path)
      run_loop_device = RunLoop::Device.new('denis', '8.3', 'udid')
      options = { :foo => :bar }
      run_loop = { :pid => 1234 }
      expect(device).to receive(:merge_start_options!).with(app, run_loop_device, options).and_return options
      expect(RunLoop).to receive(:run).with(options).and_return run_loop

      expect(device.send(:start_app_with_device_and_options, app, run_loop_device, options)).to be == run_loop
      expect(device.instance_variable_get(:@run_loop)).to be == run_loop
    end

    it '#wait_for_server_to_start' do
      device_info = {:device => :info}
      expect(device).to receive(:ensure_test_server_ready).and_return true
      expect(device).to receive(:fetch_device_info).and_return device_info
      expect(device).to receive(:extract_device_info!).with(device_info).and_return true

      expect(device.send(:wait_for_server_to_start)).to be_truthy
    end

    describe '#expect_app_installed_on_simulator' do
      let(:dummy_bridge) do
        class Calabash::DummyBridge
          def app_is_installed?

          end
        end
        Calabash::DummyBridge.new
      end

      it 'raises an error if the app is not installed' do
        expect(dummy_bridge).to receive(:app_is_installed?).and_return(false)
        expect {
          device.send(:expect_app_installed_on_simulator, dummy_bridge)
        }.to raise_error
      end

      it 'returns true if app is installed' do
        expect(dummy_bridge).to receive(:app_is_installed?).and_return(true)
        expect(device.send(:expect_app_installed_on_simulator, dummy_bridge)).to be_truthy
      end
    end

    describe 'expect_matching_sha1s#' do
      it 'raises an error if sha1s do not match' do
        app = Calabash::IOS::Application.new(IOSResources.instance.app_bundle_path)
        installed_app = Calabash::IOS::Application.new(IOSResources.instance.app_bundle_path)
        expect(installed_app).to receive(:sha1).at_least(:once).and_return('abcde')
        expect(app).to receive(:sha1).at_least(:once).and_return('fghij')
        expect {
          device.send(:expect_matching_sha1s, installed_app, app)
        }.to raise_error
      end

      it 'returns true if the sha1s match' do
        app = Calabash::IOS::Application.new(IOSResources.instance.app_bundle_path)
        installed_app = Calabash::IOS::Application.new(IOSResources.instance.app_bundle_path)
        expect(installed_app).to receive(:sha1).at_least(:once).and_return('abcde')
        expect(app).to receive(:sha1).at_least(:once).and_return('abcde')
        expect(device.send(:expect_matching_sha1s, installed_app, app)).to be_truthy
      end
    end

    describe '#merge_start_options!' do
      let(:run_loop_device) { RunLoop::Device.new('denis', '8.3', 'udid') }
      let(:app) { Calabash::IOS::Application.new(IOSResources.instance.app_bundle_path) }

      it 'sets the @start_options instance variable' do
        device.instance_variable_set(:@start_options, nil)
        expect(run_loop_device).to receive(:instruments_identifier).and_return 'instruments identifier'
        options = device.send(:merge_start_options!,
                              app,
                              run_loop_device,
                              {:foo => 'bar'})
        expect(options).to be_a_kind_of Hash
        expect(options[:foo]).to be == 'bar'
        expect(device.instance_variable_get(:@start_options)).to be == options
      end
    end
  end
end
