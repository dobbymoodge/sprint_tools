require 'csv'
require 'trello_helper'

class OverviewsHelper
  attr_accessor :trello, :bugzilla, :trello_id_to_ldap_uid

  CSV_HEADER = [ "Product(s)",
               "Product:Release",
               "Product:State",
               "Card Title",
               "URL",
               "Team",
               "Board",
               "Board URL",
               "List",
               "Status",
               "Epics",
               "Sizing",
               "Members",
               "Card ID" ]

  JIRA_DATE_FMT='%FT%TZ%z'

  def initialize(opts = nil)
    if opts
      opts.each do |k, v|
        send("#{k}=", v)
      end
    end
  end

  def card_data_to_csv_row_array(card_data)
    products = card_data[:products].keys.join("|")
    prod_rel = card_data[:products].map { |product, data| "#{product}:#{data[0]}" }.join("|")
    prod_state = card_data[:products].map { |product, data| "#{product}:#{data[1]}" }.join("|")
    card_epics = card_data[:epics].join("|")
    card_members = card_data[:members].join("|")
    [ products,
             prod_rel,
             prod_state,
             card_data[:title],
             card_data[:card_url],
             card_data[:team_name],
             card_data[:board_name],
             card_data[:board_url],
             card_data[:list],
             card_data[:status],
             card_epics,
             card_data[:card_size],
             card_members,
             card_data[:id] ]
  end

  def card_data_from_card(card, team_name, board, list, status)
    card_name = card.name
    card_size = 0
    TrelloHelper::CARD_NAME_REGEX.match(card.name) do |card_fields|
      card_name = card_fields[3].strip
      card_size = (card_fields[2] || "").strip
    end
    card_members = trello.card_members(card).map { |m| "#{m.full_name} (#{m.username})" }
    card_data = { id: card.id,
                  title: card_name,
                  card_size: card_size,
                  card_url: card.short_url,
                  team_name: team_name,
                  board_name: board.name,
                  board_url: board.url,
                  list: list.name,
                  status: status,
                  members: card_members }
    card_data[:products] = {}
    card_data[:epics] = []
    labels = trello.card_labels(card)
    label_names = labels.map { |label| label.name }
    label_names.each do |label_name|
      if label_name.start_with?('epic-')
        card_data[:epics] << label_name
      else
        TrelloHelper::RELEASE_LABEL_REGEX.match(label_name) do |fields|
          if trello.valid_products.include?(fields[2])
            product = fields[2]
            state = fields[1]
            release = fields[3]
            if status == 'Complete'
              state = 'committed'
            end
            card_data[:products][product] = [release, state]
          end
        end
      end
    end
    card_data
  end

  def jira_convert_time
    # New (non-exported) comments should have the same timestamp
    @jira_convert_time ||= Time.now.strftime(JIRA_DATE_FMT)
  end

  def jira_new_comment(text)
    "#{jira_convert_time};trello_import;#{text}"
  end

  def action_to_jira_comment(action)
    # CSV Import Date Format needs to be:
    #   "yyyy-MM-dd'T'HH:mm:ss'Z'Z"
    fmt_date = action.date.strftime(JIRA_DATE_FMT)
    author = action.member_creator_id
    if trello_id_to_ldap_uid.include?(action.member_creator_id)
      author = trello_id_to_ldap_uid[action.member_creator_id]
    else
      if trello.members_by_id.include?(action.member_creator_id)
        author = member_to_uid(trello.members_by_id[action.member_creator_id])
      end
    end
    text = action.data["text"]
    "#{fmt_date};#{author};#{text}"
  end

  def card_checklists_to_comments(card)
    checklists = trello.list_checklists(card)
    comments = checklists.map do |cl|
      comment = "Checklist: #{cl.name}\n----\n"
      comment += cl.check_items.map{ |c| "[#{c['state'] == 'complete' ? 'X' : '_'}] #{c['name']}" }.join("\n")
      jira_new_comment(comment)
    end
    comments
  end

  def member_to_uid(member)
    if trello_id_to_ldap_uid.include? member.id
      trello_id_to_ldap_uid[member.id]
    else
      "#{member.full_name} (#{member.username})"
    end
  end

  def jira_export_data_from_card(card)
    card_name = card.name
    card_size = 0
    TrelloHelper::CARD_NAME_REGEX.match(card.name) do |card_fields|
      card_name = card_fields[3].strip
      card_size = (card_fields[2] || "").strip
    end
    card_comments = [] + trello.card_comment_actions(card).map{|a| action_to_jira_comment(a)}
    # card_members = trello.card_members(card).map { |m| "#{m.full_name} (#{m.username})" }
    card_members = trello.card_members(card).map { |member| member_to_uid(member) }
    card_data = { id: card.id, # to comment
                  url: card.short_url, # to comment
                  summary: card_name,
                  description: card.desc,
                  story_points: card_size,
                  members: card_members,
                  comments: card_comments
                }
    card_data[:comments] += card_checklists_to_comments(card)
    card_data[:products] = []
    card_data[:epics] = []
    labels = trello.card_labels(card)
    label_names = labels.map { |label| label.name }
    label_names.each do |label_name|
      if label_name.start_with?('epic-')
        card_data[:epics] << label_name
      else
        TrelloHelper::RELEASE_LABEL_REGEX.match(label_name) do |fields|
          if trello.valid_products.include?(fields[2])
            product = fields[2]
            state = fields[1]
            release = fields[3]
            # if status == 'Complete'
            #   state = 'committed'
            # end
            card_data[:committment] = state
            p_r_tuple = product ? "#{product}-#{release}" : release
            card_data[:products] << p_r_tuple
          end
        end
      end
    end
    card_data
  end

  # Faster than [x, y].max
  def imax(x, y)
    x>y ? x : y
  end

  def jira_board_header(max_comments, max_members, max_epics, max_labels)
    [
      "Summary",
      "Description",
      "Story Points",
      "Status",
    ] + max_labels.times.map { "Label" } + max_epics.times.map { "Epic Link" } + max_members.times.map { "Watcher" } + max_comments.times.map { "Comment Body" }
  end

  def jira_board_row(card_data, max_comments, max_members, max_epics, max_labels)
    comments = [
      jira_new_comment("Trello Card ID: #{card_data[:id]}"),
      jira_new_comment("Trello URL: #{card_data[:url]}"),
    ]
    comments += card_data[:comments]
    # Pad comments, members, epics, labels columns to match header
    comments += (max_comments - comments.size).times.map{nil}
    members = card_data[:members] + (max_members - card_data[:members].size).times.map{nil}
    epics = card_data[:epics] + (max_epics - card_data[:epics].size).times.map{nil}
    labels = [card_data[:committment]] + card_data[:products]
    labels += (max_labels - labels.size).times.map{nil}
    row = [
      card_data[:summary],
      card_data[:description],
      card_data[:story_points],
      card_data[:status]
    ] + labels + epics + members + comments
    # row.each {|s| s.sub!('\n', '\r\n') if !s.nil?}
    row
  end

  def create_jira_board_dump(out, board_name, private=false)
    # Backlog
    # New
    # Stalled
    # Next
    lists_to_backlog = TrelloHelper::BACKLOG_STATES.merge(TrelloHelper::NEW_STATES).merge(TrelloHelper::NEXT_STATES)
    # Complete Upstream
    # Complete
    # Design
    # In Progress
    # Pending Upstream
    # Pending Merge
    lists_to_in_progress = TrelloHelper::IN_PROGRESS_STATES.merge(TrelloHelper::COMPLETE_STATES)
    lists_to_export = lists_to_backlog.merge(lists_to_in_progress)
    lists = []
    cards_data = []
    max_comments = 0
    max_members = 0
    max_epics = 0
    max_labels = 0
    board = trello.org_boards.select {|b| b.name == board_name}.first
    if !board
      raise Exception("No board matching #{board_name} found")
    end
    team_map = trello.board_id_to_team_map[board.id]
    trello.board_lists(board).each do |list|
      lists << list
    end
    lists.each do |list|
      next if !lists_to_export.include?(list.name)
      trello.list_cards(list).each do |card|
        new_card = jira_export_data_from_card(card)
        new_card[:status] = 'To Do'
        if lists_to_in_progress.include?(list.name)
          new_card[:status] = 'In Progress'
        end
        max_comments = imax(new_card[:comments].size, max_comments)
        max_members = imax(new_card[:members].size, max_members)
        max_epics = imax(new_card[:epics].size, max_epics)
        max_labels = imax(new_card[:products].size, max_labels)
        cards_data << new_card
      end
    end
    max_comments += 2
    max_labels += 1
    header = jira_board_header(max_comments, max_members, max_epics, max_labels)
    CSV.open(out, "wb") do |csv|
      csv << header
      cards_data.each do |card_data|
        csv << jira_board_row(card_data, max_comments, max_members, max_epics, max_labels)
      end
    end
  end

  def create_raw_overview_data(out)
    cards_data = []
    lists_for_team_boards = []
    # Leave this for ease of testing
    # ["clusterlifecycle","continuousinfra","customersuccess"].each do |team|
    trello.teams.each do |team_name, team|
      if !team[:exclude_from_releases_overview]
        trello.team_boards(team_name).each do |board|
          trello.board_lists(board).each do |list|
            lists_for_team_boards << [team_name.to_s, board, list]
          end
        end
      end
    end
    lists_for_team_boards.each do |team_name, board, list|
      if trello.list_for_completed_work?(list.name)
        status = 'Complete'
      elsif trello.list_for_in_progress_work?(list.name)
        status = 'In Progress'
      end
      trello.list_cards(list).each do |card|
        cards_data << card_data_from_card(card, team_name, board, list, status)
      end
    end
    CSV.open(out, "wb") do |csv|
      csv << CSV_HEADER
      cards_data.each do |card_data|
        csv << card_data_to_csv_row_array(card_data)
      end
    end
  end

  def create_releases_overview(out)
    extname = File.extname out
    filename = File.basename out, extname
    dirname = File.dirname out

    ((trello.other_products ? trello.other_products : []) + [nil]).each do |product|
      erb = ERB.new(File.open('templates/releases_overview.erb', "rb").read)
      file = nil
      if product
        file = File.join(dirname, "#{filename}_#{product}#{extname}")
      else
        file = out
      end
      File.open(file, 'w') { |f| f.write(erb.result(binding)) }
    end
  end

  def create_teams_overview(out)
    extname = File.extname out
    filename = File.basename out, extname
    dirname = File.dirname out

    (trello.teams.keys + [nil]).each do |team|
      erb = ERB.new(File.open('templates/teams_overview.erb', "rb").read)
      file = nil
      if team
        file = File.join(dirname, "#{filename}_#{team}#{extname}")
      else
        file = out
      end
      File.open(file, 'w') { |f| f.write(erb.result(binding)) }
    end
  end

  def create_developers_overview(out)
    extname = File.extname out
    filename = File.basename out, extname
    dirname = File.dirname out

    (trello.teams.keys + [nil]).each do |team|
      erb = ERB.new(File.open('templates/developers_overview.erb', "rb").read)
      file = nil
      if team
        file = File.join(dirname, "#{filename}_#{team}#{extname}")
      else
        file = out
      end
      File.open(file, 'w') { |f| f.write(erb.result(binding)) }
    end
  end

  def create_labels_overview(out)
    erb = ERB.new(File.open('templates/labels_overview.erb', "rb").read)
    File.open(out, 'w') { |f| f.write(erb.result(binding)) }
  end

  def create_roadmap_overview(out)
    erb = ERB.new(File.open('templates/roadmap_overview.erb', "rb").read)
    File.open(out, 'w') { |f| f.write(erb.result(binding)) }
  end
end
