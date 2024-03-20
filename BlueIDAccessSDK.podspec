Pod::Spec.new do |s|
  s.name = 'BlueIDAccessSDK'
  s.version = '0.101.0'
  s.license = { :type => 'MIT' }
  s.summary = 'BlueID Access SDK for Swift'
  s.homepage = 'https://www.blue-id.com'
  s.author = 'BlueID GmbH'
  s.source = { :git => 'https://github.com/blueidhq/BlueIDAccessSDKSwift.git', :tag => 'v' + s.version.to_s }

  s.requires_arc = true
  s.ios.deployment_target = '14.0'
  # s.osx.deployment_target = '10.13'
  # s.watchos.deployment_target = '8.0'

  s.source_files = 'Sources/BlueIDAccessSDK/**/*.swift'

  s.vendored_frameworks = 'CBlueIDAccess.xcframework'

  s.swift_version = '5.8'

  s.dependency 'SwiftProtobuf', '1.24.0'
end
