require 'json'

FILES = [ 'ansible-service-broker.json', 'atomicopenshift-roadmap.json', 'blogs-and-screencasts.json', 'cartridge.json', 'cluster-infrastructure.json', 'cluster-lifecycle.json', 'cockpit.json', 'container-security.json', 'containers.json', 'container-tools.json', 'continuous-infra.json', 'core-operations.json', 'customer-success.json', 'developer-experience.json', 'e2e-provider-integration.json', 'evg.json', 'hack-days.json', 'how-we-use-trello.json', 'integration-services.json', 'kube-origin.json', 'networking.json', 'ocp-docs-content-plan.json', 'online.json', 'online-marketing-product-requests.json', 'openshift-blog.json', 'openshift-developer-challenge-2014.json', 'openshift-docs-planning.json', 'openshift-org.json', 'openshift-origin-release-engineering.json', 'openshift-p-sap.json', 'partner-integrations.json', 'platform-infrastructure.json', 'platform-management.json', 'private-atomicopenshift-roadmap.json', 'private-cluster-infrastructure.json', 'private-cluster-lifecycle.json', 'private-container-best-practices.json', 'private-container-security.json', 'private-containers.json', 'private-continuous-delivery.json', 'private-continuous-infra.json', 'private-developer-experience.json', 'private-e2e-application-integration.json', 'private-e2e-provider-integration.json', 'private-hack-day-cards.json', 'private-integration-services.json', 'private-networking.json', 'private-online.json', 'private-platform-infrastructure.json', 'private-platform-management.json', 'private-storage.json', 'private-storage-uxp.json', 'private-user-interface.json', 'scalability.json', 'sqe.json', 'storage.json', 'themes.json', 'user-interface.json' ]

to_del = {}

weird_dups = []
FILES.each do |fn|
  asb = JSON.load(IO.read(fn))
  asbcls = asb['checklists']
  messed_up = asbcls.select{|cl| cl['checkItems'].any?{|ci| ci['name'].include? 'https://trello.com/c/'}}
  mum = {}
  messed_up.each do |cl|
    rval={}
    while !cl['checkItems'].empty? do
      ii = cl['checkItems'].pop
      #puts 1, ii
      matches = ii['name'].match(/(https:\/\/trello\.com\/c\/[^\/]+)\//)
      mstr = matches[1] if matches && matches[1]
      # puts 2, mstr
      idx = cl['checkItems'].find_index{|jj| jj['name'].include? mstr if mstr && jj['name']}
      # puts 3, idx
      if idx
        # puts 4
        mm = cl['checkItems'].delete_at(idx)
        # puts 5, mm
        # if !(mm['name'].include?("%") || ii['name'].include?("%"))
        #   wd = {}
        #   wd['idCard'] = cl['idCard']
        #   wd[mm['id']] = mm
        #   wd[ii['id']] = ii
        #   weird_dups << wd
        # else
          if mm['name'].size >= ii['name'].size
            # puts 6
            mum[mm['id']] = mm
          else
            # puts 7
            mum[ii['id']] = ii
          end
        #end
      end
    end
  end
  mum.delete_if{|x| x.empty?}
  to_del[asb['url']] = mum if !mum.empty?
end

# to_del.each do |kk|
#   kk.each do |jj|
#     puts " --- " if !jj.empty?
#     jj.each{|ii| puts "#{ii[0]}, #{ii[1]}, #{ii[2]}" if ii[1]}
#   end
# end

# puts "\n\n --- Weird dups ---\n\n"


# weird_dups.each do |ii|
#   puts "#{ii[0]}, #{ii[1]}, #{ii[2]}" if ii[1]
# end

# res = {"to_delete" => to_del}.to_json#, "weird_dups" => weird_dups}.to_json
res = {"to_delete" => to_del, "weird_dups" => weird_dups}.to_json
#res = {"weird_dups" => weird_dups}.to_json
puts res
