Pod::Spec.new do |s|
    s.name = 'BlueIDAccessSDK'
    s.version = '1.35.0'
    s.summary = 'BlueID Access SDK'
    s.homepage = 'https://www.blue-id.com'
    s.license = { :type => 'MIT' }
    s.author = { 'BlueIDAccessSDK' => 'BlueID GmbH' }
    s.source = { :git => 'https://github.com/blueidhq/BlueIDAccessSDKSwift.git', :tag => 'v' + s.version.to_s }
    s.vendored_frameworks = 'BlueIDAccessSDK.xcframework'
    s.requires_arc = true
    s.ios.deployment_target = '14.0'
    s.swift_version = '5.8'
    s.dependency 'SwiftProtobuf', '1.24.0'
    s.dependency 'iOSDFULibrary', '4.15.0'
  end