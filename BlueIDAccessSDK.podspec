Pod::Spec.new do |s|
    s.name                = 'BlueIDAccessSDK'
    s.version             = '1.0.0'
    s.summary             = 'BlueID Access SDK'
    s.homepage            = 'https://www.blue-id.com'
    s.license             = { :type => 'MIT' }
    s.author              = { 'BlueIDAccessSDK' => 'BlueID GmbH' }
    s.source              = { :http => "file:///Users/Downloads/Frameworks.zip" }
    s.vendored_frameworks = 'BlueIDAccessSDK.xcframework'
  end