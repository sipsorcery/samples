require 'httpclient'
require 'json'
require 'UUIDTools'

puts "sipsorcery get notifications sample"

notificationsURL = "http://localhost:8080/notificationspull.svc/rest/"
myUsername = "username"
myPassword = "password"
addressID = UUIDTools::UUID.random_create
filter = "event%2053"

client = HTTPClient.new
resp = client.get_content("#{notificationsURL}login?username=#{myUsername}&password=#{myPassword}")
authID = resp.delete('"')
puts "authID=#{authID}"

resp = client.get_content("#{notificationsURL}subscribeforaddress?subject=controlclient&filter=#{filter}&addressid=#{addressID}", nil, "authID" => authID)
puts "Notifications subscribe response=#{resp}"

30.times do
  resp = client.get_content("#{notificationsURL}getnotificationsforaddress?addressid=#{addressID}", nil, "authID" => authID)
  if !resp.empty?
    notifications = JSON.parse(resp.to_s)
    notifications[0]["Value"].each do |notification|
      puts notification.chomp
    end
  end
  sleep(1)
end

# Close the notifications connection.
client.get_content("#{notificationsURL}closeconnectionforaddress?addressid=#{addressID}", nil, "authID" => authID)

puts "finished"