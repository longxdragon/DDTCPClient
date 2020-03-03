
Pod::Spec.new do |s|

  s.name         = "DDTCPClient"
  s.version      = "0.0.4"
  s.summary      = "A client of socket"

  s.homepage     = "https://github.com/longxdragon/DDTCPClient"
  s.license      = "MIT"

  s.author       = { "longxdragon" => "longxdragon@163.com" }
  s.platform     = :ios, "8.0"

  s.source       = { :git => "https://github.com/longxdragon/DDTCPClient.git", :tag => "#{s.version}" }
  s.source_files = "Source/DDTCPClient/*.{h,m}"
  
  s.framework    = "Foundation"
  s.requires_arc = true

  s.dependency 'CocoaAsyncSocket', '~> 7.6.2'
  s.dependency 'AFNetworking/Reachability', '2.6.3'

  # s.static_framework = true

end
