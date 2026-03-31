Pod::Spec.new do |s|
  s.name             = 'CBMerchantSDK'
  s.version          = '1.0.0'
  s.summary          = 'CBMerchant iOS SDK'

  s.description      = <<-DESC
                       CBMerchantSDK framework for iOS
                       DESC

  s.homepage         = 'https://github.com/KayesSSL/CBMerchantSDK.git'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Imrul Kayes' => 'imrul.kayes@sslwireless.com' }
  s.platform         = :ios, '15.0'
  s.source           = { :path => '.' }
  s.source_files     = 'CBMerchantSDK/**/*.{swift,h}'
  s.swift_version    = '5.0'

  # Include resource bundles and assets
  s.resource_bundles = {
    'CBSDKResources' => [
      'CBMerchantSDK/CBSDK/Assets/CBSDKResources.bundle/**/*',
      'CBMerchantSDK/CBSDK/Assets/Assets.xcassets',
      'CBMerchantSDK/CBSDK/Assets/Fonts/*.ttf',
      'CBMerchantSDK/CBSDK/Assets/Fonts/*.otf'
    ]
  }
end
