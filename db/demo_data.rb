# frozen_string_literal: true

module RedmineReporting
  class DemoData
    PROJECT_IDENTIFIER = "reporting-demo"
    TRACKER_NAMES = ["Feature request", "Support request", "Bug"].freeze
    # Name, closed flag. Positions follow Redmine's default workflow order.
    STATUSES = [
      ["New", false], ["In Progress", false], ["Feedback", false],
      ["Resolved", false], ["Closed", true], ["Rejected", true]
    ].freeze
    ROOT_STATUS_NAMES = ["New", "In Progress", "Resolved", "Closed"].freeze
    PRIORITY_NAMES = ["Low", "Normal", "High", "Urgent", "Immediate"].freeze
    COLLABORATORS = [
      ["reporting-alice", "Alice", "Martin"],
      ["reporting-bilal", "Bilal", "Petit"],
      ["reporting-claire", "Claire", "Durand"],
      ["reporting-david", "David", "Leroy"],
      ["reporting-emma", "Emma", "Moreau"]
    ].freeze
    ACTIVITY_NAMES = ["Analysis", "Development", "Testing", "Support"].freeze
    # Initial days and July 1 refill per project and tracker: the parent project keeps a small
    # credit of its own, each subproject has the credits of its activity.
    CREDIT_DAYS = {
      "reporting-demo" => {"Feature request" => [30, 5], "Support request" => [20, nil], "Bug" => [20, nil]},
      "reporting-demo-maintenance" => {"Bug" => [70, 10], "Support request" => [40, nil]},
      "reporting-demo-evolution" => {"Feature request" => [80, 20]}
    }.freeze

    MANAGER_ROLE = "Reporting Manager"
    DEVELOPER_ROLE = "Reporting Developer"
    ROLE_PERMISSIONS = {
      MANAGER_ROLE => %i[view_issues add_issues edit_issues add_issue_notes manage_versions view_time_entries
                         log_time edit_time_entries view_reporting manage_reporting save_queries],
      DEVELOPER_ROLE => %i[view_issues add_issues edit_issues add_issue_notes view_time_entries log_time
                           edit_own_time_entries view_reporting]
    }.freeze
    # Only managers close or reject; journals below follow these transitions.
    WORKFLOW = {
      "New" => ["In Progress", "Feedback", "Rejected"],
      "In Progress" => ["Feedback", "Resolved", "Rejected"],
      "Feedback" => ["In Progress", "Resolved", "Rejected"],
      "Resolved" => ["In Progress", "Feedback", "Closed"],
      "Closed" => ["In Progress"],
      "Rejected" => ["New"]
    }.freeze
    MANAGER_ONLY_STATUSES = ["Closed", "Rejected"].freeze

    # Two subprojects with distinct shapes: a busy maintenance run and a slower release-driven product.
    SUBPROJECTS = [
      {
        identifier: "reporting-demo-maintenance", name: "Maintenance", code: "MNT", seed: 11,
        members: [["reporting-alice", MANAGER_ROLE], ["reporting-bilal", DEVELOPER_ROLE], ["reporting-david", DEVELOPER_ROLE]],
        trackers: {"Bug" => 5, "Support request" => 4, "Feature request" => 1},
        volumes: [9, 12, 7, 5, 14, 11, 8, 16, 10, 6, 13, 9],
        versions: :quarterly
      },
      {
        identifier: "reporting-demo-evolution", name: "Évolutions", code: "EVO", seed: 23,
        members: [["reporting-claire", MANAGER_ROLE], ["reporting-emma", DEVELOPER_ROLE], ["reporting-alice", DEVELOPER_ROLE]],
        trackers: {"Feature request" => 6, "Bug" => 2, "Support request" => 1},
        volumes: [3, 5, 2, 6, 4, 7, 3, 2, 5, 8, 4, 6],
        versions: :releases
      }
    ].freeze

    # Delays are in days before the next transition; probabilities drive the workflow branches.
    PROFILES = {
      "Bug" => {triage: 0.1..2.0, work: 0.5..6.0, feedback: 1.0..5.0, validation: 1.0..4.0,
                reject: 0.05, parked: 0.04, ask_feedback: 0.3, stale: 0.15, reopen: 0.2, estimate: 2.0..16.0, estimated: 0.85,
                hours: 0.5..4.0, activity: "Development", resolved_note: "Correctif livré en recette."},
      "Support request" => {triage: 0.05..1.0, work: 0.2..2.0, feedback: 1.0..8.0, validation: 0.5..3.0,
                            reject: 0.1, parked: 0.05, ask_feedback: 0.55, stale: 0.2, reopen: 0.05, estimate: 1.0..6.0, estimated: 0.5,
                            hours: 0.25..2.0, activity: "Support", resolved_note: "Réponse apportée au demandeur."},
      "Feature request" => {triage: 2.0..20.0, work: 5.0..30.0, feedback: 2.0..10.0, validation: 3.0..12.0,
                            reject: 0.08, parked: 0.12, ask_feedback: 0.35, stale: 0.2, reopen: 0.15, estimate: 16.0..80.0, estimated: 0.95,
                            hours: 1.0..7.0, activity: "Development", resolved_note: "Développement livré en recette."}
    }.freeze
    PRIORITY_WEIGHTS = {"Low" => 2.0, "Normal" => 5.0, "High" => 3.0, "Urgent" => 1.5, "Immediate" => 0.5}.freeze
    PRIORITY_SPEED = {"Low" => 1.6, "Normal" => 1.0, "High" => 0.7, "Urgent" => 0.45, "Immediate" => 0.25}.freeze
    SUBJECTS = {
      "Bug" => [
        "Erreur 500 à l'export PDF des factures", "Filtre par date ignoré dans la liste des commandes",
        "Doublons dans la synchronisation des contacts", "Session expirée trop tôt sur mobile",
        "Arrondi incorrect sur les totaux TTC", "Pièce jointe non téléchargeable depuis Safari",
        "Notification e-mail envoyée deux fois", "Lenteur du tableau de bord au-delà de 500 lignes",
        "Tri alphabétique incorrect avec les accents", "Import CSV bloqué sur le séparateur point-virgule"
      ],
      "Support request" => [
        "Création d'un compte pour un nouvel arrivant", "Réinitialisation du mot de passe d'un utilisateur",
        "Question sur le paramétrage des droits", "Extraction ponctuelle des ventes du trimestre",
        "Aide à la configuration du SSO", "Ajout d'un champ dans l'export mensuel",
        "Purge des brouillons obsolètes", "Explication d'un écart de stock"
      ],
      "Feature request" => [
        "Export Excel des tableaux de bord", "Tableau de bord des indicateurs commerciaux",
        "Signature électronique des bons de livraison", "API de consultation des stocks",
        "Mode hors ligne pour l'application terrain", "Relances automatiques des devis",
        "Historique des modifications des fiches clients", "Connecteur avec la comptabilité",
        "Planification des tournées", "Personnalisation des modèles d'e-mail"
      ]
    }.freeze

    def self.load
      new.load
    end

    def load
      unless (Rails.env.development? || Rails.env.test?) && ENV["REPORTING_DEMO_DATABASE"] == "disposable"
        raise "Demo data requires a disposable development/test database (REPORTING_DEMO_DATABASE=disposable)"
      end
      # An empty instance is the only safe target: this seed configures global dictionaries.
      if Project.exists? && !Project.exists?(identifier: PROJECT_IDENTIFIER)
        raise "Refusing to seed an existing business database"
      end
      allowed = [PROJECT_IDENTIFIER, *SUBPROJECTS.map { |definition| definition.fetch(:identifier) }]
      raise "Refusing unrelated projects" if Project.where.not(identifier: allowed).exists?
      Mailer.with_deliveries(false) { ActiveRecord::Base.transaction { seed } }
    end

    private

    def seed
      user = User.active.find_by(admin: true) || User.active.first
      raise "An active Redmine user is required to seed demo issues" unless user

      @admin = user
      @now = Time.current
      @first_month = Date.current.beginning_of_month >> -11
      statuses = ensure_statuses
      trackers = ensure_trackers(statuses.fetch("New"))
      priorities = ensure_priorities
      users = ensure_collaborators
      # Redmine validates assignees as active. Activation is only visible inside
      # this transaction; accounts are locked again before anything is committed.
      users.each { |collaborator| collaborator.update!(status: User::STATUS_ACTIVE) }
      activities = ensure_activities
      roles = ensure_roles
      ensure_workflows(roles, trackers, statuses)

      project = Project.find_or_initialize_by(identifier: PROJECT_IDENTIFIER)
      project.assign_attributes(
        name: "Reporting Demo",
        description: "Données de démonstration RedmineReporting",
        is_public: true
      )
      project.save!
      project.trackers = trackers
      project.enabled_module_names = (project.enabled_module_names + %w[issue_tracking reporting time_tracking]).uniq
      project.save!
      users.each_with_index { |member, index| ensure_membership(project, member, roles.fetch(index.zero? ? MANAGER_ROLE : DEVELOPER_ROLE)) }
      ensure_root_versions(project)

      create_issues(project, trackers, statuses.values_at(*ROOT_STATUS_NAMES), priorities, users, activities, user)
      SUBPROJECTS.each do |definition|
        subproject = ensure_subproject(project, trackers, definition)
        members = definition[:members].map do |login, role_name|
          member = users.find { |candidate| candidate.login == login }
          ensure_membership(subproject, member, roles.fetch(role_name))
          member
        end
        versions = ensure_subproject_versions(subproject, definition)
        create_subproject_issues(subproject, definition, members, versions,
                                 trackers.index_by(&:name), statuses, priorities.index_by(&:name), activities.index_by(&:name))
        create_follow_up_entries(subproject, definition, members.first, activities.index_by(&:name))
        subproject.versions.where.not(id: versions.map(&:id)).each { |version| version.destroy if version.fixed_issues.empty? }
        close_past_versions(versions)
        create_credit_policies(subproject, trackers)
      end
      create_credit_policies(project, trackers)
      users.each { |collaborator| collaborator.update!(status: User::STATUS_LOCKED) }
      project
    end

    def ensure_statuses
      STATUSES.each_with_index.to_h do |(name, closed), index|
        status = IssueStatus.find_or_initialize_by(name: name)
        status.assign_attributes(is_closed: closed, position: index + 1)
        status.save!
        [name, status]
      end
    end

    def ensure_trackers(default_status)
      TRACKER_NAMES.each_with_index.map do |name, index|
        tracker = Tracker.find_or_initialize_by(name: name)
        tracker.assign_attributes(default_status: default_status, position: index + 1)
        tracker.save!
        tracker
      end
    end

    def ensure_priorities
      PRIORITY_NAMES.each_with_index.map do |name, index|
        priority = IssuePriority.find_or_initialize_by(name: name)
        priority.assign_attributes(
          position: index + 1,
          is_default: name == "Normal",
          active: true
        )
        priority.save!
        priority
      end
    end

    def ensure_collaborators
      COLLABORATORS.map do |login, first_name, last_name|
        user = User.find_or_initialize_by(login: login)
        if user.persisted? && (user.admin? || user.mail != "#{login}@example.invalid")
          raise "Demo user collision: #{login}"
        end
        user.assign_attributes(
          firstname: first_name,
          lastname: last_name,
          mail: "#{login}@example.invalid",
          language: "fr",
          status: User::STATUS_LOCKED,
          admin: false
        )
        if user.new_record?
          password = SecureRandom.base64(36)
          user.password = password
          user.password_confirmation = password
        end
        user.save!
        user
      end
    end

    def ensure_activities
      ACTIVITY_NAMES.each_with_index.map do |name, index|
        activity = TimeEntryActivity.find_or_initialize_by(name: name, project_id: nil)
        activity.assign_attributes(position: index + 1, active: true, is_default: name == "Development")
        activity.save!
        activity
      end
    end

    def ensure_roles
      ROLE_PERMISSIONS.to_h do |name, permissions|
        role = Role.find_or_initialize_by(name: name)
        role.assign_attributes(assignable: true, issues_visibility: "all", time_entries_visibility: "all",
                               users_visibility: "all", permissions: permissions)
        role.save!
        [name, role]
      end
    end

    def ensure_workflows(roles, trackers, statuses)
      roles.each do |role_name, role|
        trackers.each do |tracker|
          WORKFLOW.each do |old_name, new_names|
            new_names.each do |new_name|
              next if role_name == DEVELOPER_ROLE && MANAGER_ONLY_STATUSES.include?(new_name)

              WorkflowTransition.find_or_create_by!(role_id: role.id, tracker_id: tracker.id,
                                                    old_status_id: statuses.fetch(old_name).id,
                                                    new_status_id: statuses.fetch(new_name).id,
                                                    author: false, assignee: false)
            end
          end
        end
      end
    end

    def ensure_membership(project, user, role)
      member = Member.find_or_initialize_by(project_id: project.id, user_id: user.id)
      return if member.persisted? && member.role_ids.include?(role.id)

      member.role_ids = member.role_ids | [role.id]
      member.save!
    end

    def ensure_subproject(project, trackers, definition)
      subproject = Project.find_or_initialize_by(identifier: definition[:identifier])
      subproject.assign_attributes(
        name: "#{project.name} · #{definition[:name]}",
        description: "Sous-projet de démonstration pour les filtres RedmineReporting.",
        parent: project,
        is_public: true
      )
      subproject.save!
      subproject.trackers = trackers
      subproject.enabled_module_names = (subproject.enabled_module_names + %w[issue_tracking reporting time_tracking]).uniq
      subproject.save!
      subproject
    end

    def ensure_root_versions(project)
      ["Release 1.0", "Release 2.0"].each do |name|
        version = project.versions.find_or_initialize_by(name: name)
        version.assign_attributes(status: "open", sharing: "descendants", effective_date: Date.current.end_of_year)
        version.save!
      end
    end

    # Versions stay open while issues are saved, then past ones are locked or closed.
    def ensure_subproject_versions(subproject, definition)
      specifications =
        if definition[:versions] == :quarterly
          quarter = @first_month.beginning_of_quarter
          quarters = []
          while quarter <= (Date.current >> 3)
            quarters << ["MCO T#{(quarter.month - 1) / 3 + 1} #{quarter.year}", quarter.end_of_quarter]
            quarter >>= 3
          end
          quarters
        else
          [["Release 1.0", 3], ["Release 1.1", 7], ["Release 2.0", 12], ["Release 2.1", 15]].map do |name, offset|
            [name, (@first_month >> offset).end_of_month]
          end
        end
      versions = specifications.map do |name, effective_date|
        version = subproject.versions.find_or_initialize_by(name: name)
        version.assign_attributes(status: "open", sharing: "descendants", effective_date: effective_date,
                                  description: "Version de démonstration")
        version.save!
        version
      end
      versions
    end

    def close_past_versions(versions)
      versions.each do |version|
        next unless version.effective_date < Date.current

        version.update!(status: version.fixed_issues.open.exists? ? "locked" : "closed")
      end
    end

    def create_issues(project, trackers, statuses, priorities, users, activities, user)
      first_month = Date.current.beginning_of_month >> -11

      12.times do |month_offset|
        month = first_month >> month_offset
        trackers.each_with_index do |tracker, tracker_index|
          5.times do |issue_offset|
            sequence = month_offset * trackers.length * 5 + tracker_index * 5 + issue_offset
            status = statuses[(month_offset + tracker_index + issue_offset) % statuses.length]
            created_on = Time.zone.local(month.year, month.month, 3 + issue_offset * 5, 9 + tracker_index)
            subject = "Demo #{month.strftime('%Y-%m')} #{tracker.name} #{issue_offset + 1}"
            issue = project.issues.find_or_initialize_by(subject: subject)
            issue.assign_attributes(
              tracker: tracker,
              status: status,
              priority: priorities[(month_offset + tracker_index + issue_offset) % priorities.length],
              author: user,
              description: "Ticket de démonstration pour les graphiques RedmineReporting.",
              start_date: created_on.to_date,
              due_date: created_on.to_date + 14.days,
              estimated_hours: 12 + (sequence % 8) * 4,
              done_ratio: status.is_closed? ? 100 : (status.name == "Resolved" ? 80 : 20),
              created_on: created_on,
              updated_on: created_on,
              closed_on: status.is_closed? ? created_on + 2.days : nil
            )
            issue.save!
            issue.update_columns(
              created_on: created_on,
              updated_on: created_on,
              closed_on: status.is_closed? ? created_on + 2.days : nil
            )
            create_time_entries(project, issue, users, activities, sequence, created_on)
          end
        end
      end
    end

    def create_time_entries(project, issue, users, activities, sequence, created_on)
      entry_count = sequence % 3 == 0 ? 2 : 1
      entry_count.times do |entry_index|
        comment = "Reporting demo #{issue.id} #{entry_index + 1}"
        entry = TimeEntry.find_or_initialize_by(project: project, issue: issue, comments: comment)
        entry.assign_attributes(
          user: users[(sequence + entry_index) % users.length],
          author: users[(sequence + entry_index) % users.length],
          activity: activities[(sequence + entry_index) % activities.length],
          hours: 1.0 + ((sequence + entry_index) % 5) * 0.5,
          spent_on: created_on.to_date + entry_index + 1,
          comments: comment
        )
        entry.save!
      end
    end

    # Each issue replays a workflow story: journals, assignees, postponed versions and time spent
    # follow the same timeline, so histories, closure dates and charts agree.
    def create_subproject_issues(subproject, definition, members, versions, trackers, statuses, priorities, activities)
      kept_ids = []
      12.times do |month_offset|
        month = @first_month >> month_offset
        # Seeded per month: rerunning replays the same stories, only extended up to today.
        random = Random.new(definition[:seed] * 100_000 + month.year * 12 + month.month)
        definition[:volumes][month_offset].times do |index|
          story = build_story(definition, month, index, members, versions, random)
          next unless story

          kept_ids << save_story(subproject, story, trackers, statuses, priorities, activities).id
        end
      end
      subproject.issues.where.not(id: kept_ids).find_each do |issue|
        issue.time_entries.delete_all
        issue.reload.destroy
      end
    end

    def build_story(definition, month, index, members, versions, random)
      last_day = month == Date.current.beginning_of_month ? Date.current.day : month.end_of_month.day
      created_on = Time.zone.local(month.year, month.month, random.rand(1..last_day), random.rand(8..17), random.rand(0..59))
      return nil if created_on > @now

      tracker_name = weighted(random, definition[:trackers])
      priority_name = weighted(random, PRIORITY_WEIGHTS)
      profile = PROFILES.fetch(tracker_name)
      manager = members.first
      author = random.rand < 0.25 ? @admin : members[random.rand(members.length)]
      subjects = SUBJECTS.fetch(tracker_name)
      version = initial_version(definition, versions, tracker_name, created_on, random)
      estimated = random.rand < profile[:estimated] ? (random.rand(profile[:estimate]) * 2).round / 2.0 : nil

      {
        subject: "#{definition[:code]}-#{month.strftime('%y%m')}-#{format('%02d', index + 1)} · #{subjects[random.rand(subjects.length)]}",
        tracker: tracker_name, priority: priority_name, author: author, created_on: created_on,
        version: version, estimated_hours: estimated, profile: profile,
        steps: workflow_steps(profile, PRIORITY_SPEED.fetch(priority_name), created_on, members, manager, author, random),
        random: random, members: members, manager: manager, versions: versions
      }
    end

    def workflow_steps(profile, speed, created_on, members, manager, author, random)
      steps = []
      state = {status: "New", assignee: nil, done_ratio: 0}
      time = created_on
      advance = lambda do |range, status, user, notes, assignee: state[:assignee], done_ratio: state[:done_ratio]|
        time += (random.rand(range) * speed).days
        return false if time > @now

        steps << {at: time, user: user, notes: notes, status: status, assignee: assignee, done_ratio: done_ratio}
        state = {status: status, assignee: assignee, done_ratio: done_ratio}
        true
      end
      developers = members.drop(1)

      if random.rand < profile[:reject]
        advance.call(profile[:triage], "Rejected", manager, "Hors périmètre du contrat : demande rejetée.", done_ratio: 0)
        return steps
      end
      # Low and normal priorities may wait in the backlog without ever being triaged.
      return steps if speed >= 1.0 && random.rand < profile[:parked]

      worker = random.rand < 0.2 ? manager : developers[random.rand(developers.length)]
      return steps unless advance.call(profile[:triage], "In Progress", manager, "Prise en charge.", assignee: worker, done_ratio: 10)

      rounds = 0
      loop do
        if rounds < 2 && random.rand < profile[:ask_feedback]
          return steps unless advance.call(profile[:work], "Feedback", state[:assignee], "En attente d'un retour du demandeur.", done_ratio: 40)
          # Some requesters never answer: the issue ages in Feedback.
          return steps if random.rand < profile[:stale]

          others = members - [state[:assignee]]
          next_worker = random.rand < 0.25 ? others[random.rand(others.length)] : state[:assignee]
          notes = next_worker == state[:assignee] ? "Retour reçu, reprise du traitement." : "Retour reçu ; réaffectation pour équilibrer la charge."
          return steps unless advance.call(profile[:feedback], "In Progress", author, notes, assignee: next_worker, done_ratio: 50)
        end
        return steps unless advance.call(profile[:work], "Resolved", state[:assignee], profile[:resolved_note], done_ratio: 90)
        break unless rounds < 2 && random.rand < profile[:reopen]

        rounds += 1
        return steps unless advance.call(profile[:validation], "In Progress", author, "Anomalie constatée en recette, reprise.", done_ratio: 60)
      end
      advance.call(profile[:validation], "Closed", manager, "Validé par le demandeur, clôture.", done_ratio: 100)
      steps
    end

    def initial_version(definition, versions, tracker_name, created_on, random)
      date = created_on.to_date
      if definition[:versions] == :quarterly
        return nil if tracker_name == "Support request" && random.rand < 0.7

        lead = tracker_name == "Feature request" ? 45 : 15
        versions.find { |version| version.effective_date >= date + lead }
      else
        return nil if tracker_name == "Support request"

        lead = tracker_name == "Feature request" ? 30 : 7
        versions.find { |version| version.effective_date >= date + lead }
      end
    end

    # Unfinished issues are moved to the next version the day after a missed due date.
    def postponements(story)
      version = story[:version]
      return [] unless version

      closing = story[:steps].reverse.find { |step| %w[Closed Rejected].include?(step[:status]) }
      finished_at = closing ? closing[:at] : @now
      moves = []
      while version
        following = story[:versions].find { |candidate| candidate.effective_date > version.effective_date }
        at = Time.zone.local(version.effective_date.year, version.effective_date.month, version.effective_date.day, 9) + 1.day
        break unless following && at < finished_at

        moves << {at: at, user: story[:manager], version: following,
                  notes: "Reporté sur #{following.name} : non livré pour l'échéance du #{I18n.l(version.effective_date, locale: :fr)}."}
        version = following
      end
      moves
    end

    def save_story(subproject, story, trackers, statuses, priorities, activities)
      events = (story[:steps] + postponements(story)).sort_by { |event| event[:at] }
      state = {status: "New", assignee: nil, done_ratio: 0, version: story[:version]}
      final = events.each_with_object(state.dup) do |event, current|
        current[:status] = event[:status] if event.key?(:status)
        current[:assignee] = event[:assignee] if event.key?(:assignee)
        current[:done_ratio] = event[:done_ratio] if event.key?(:done_ratio)
        current[:version] = event[:version] if event.key?(:version)
      end
      final_status = statuses.fetch(final[:status])
      closed_event = events.reverse.find { |event| event[:status] && statuses.fetch(event[:status]).is_closed? }
      closed_on = final_status.is_closed? ? closed_event[:at] : nil
      updated_on = events.last ? events.last[:at] : story[:created_on]
      start_date = story[:created_on].to_date
      tracker = trackers.fetch(story[:tracker])

      issue = subproject.issues.find_or_initialize_by(subject: story[:subject])
      if issue.persisted?
        issue.journals.destroy_all
        issue.time_entries.delete_all
      end
      issue.assign_attributes(
        tracker: tracker,
        status: final_status,
        priority: priorities.fetch(story[:priority]),
        author: story[:author],
        assigned_to: final[:assignee],
        fixed_version: final[:version],
        description: "Scénario de démonstration : historique, affectations et temps passés cohérents.",
        start_date: start_date,
        due_date: final[:version]&.effective_date&.then { |date| [date, start_date].max } || start_date + story[:random].rand(7..30),
        estimated_hours: story[:estimated_hours],
        done_ratio: final[:done_ratio]
      )
      issue.notify = false
      issue.save!
      create_journals(issue, events, state, statuses)
      create_story_time_entries(issue, story, activities)
      # Journals save the issue again: update_columns would be skipped by its stale lock_version.
      Issue.where(id: issue.id).update_all(created_on: story[:created_on], updated_on: updated_on, closed_on: closed_on)
      issue
    end

    def create_journals(issue, events, state, statuses)
      current = state.dup
      events.each do |event|
        journal = issue.journals.build(user: event[:user], notes: event[:notes], created_on: event[:at])
        journal.updated_on = event[:at] if journal.has_attribute?(:updated_on)
        journal.notify = false
        {status: "status_id", assignee: "assigned_to_id", done_ratio: "done_ratio", version: "fixed_version_id"}.each do |key, attribute|
          next unless event.key?(key) && event[key] != current[key]

          old_value, new_value = [current[key], event[key]].map do |value|
            case key
            when :status then statuses.fetch(value).id
            when :done_ratio then value
            else value&.id
            end
          end
          journal.details.build(property: "attr", prop_key: attribute, old_value: old_value&.to_s, value: new_value&.to_s)
          current[key] = event[key]
        end
        journal.save!
      end
    end

    # Time is logged by whoever holds the issue while it is being worked on, and by a tester once resolved.
    def create_story_time_entries(issue, story, activities)
      random = story[:random]
      profile = story[:profile]
      steps = story[:steps]
      if story[:tracker] == "Feature request" && steps.any?
        log_time(issue, story[:manager], activities.fetch("Analysis"), story[:created_on], steps.first[:at], profile, random, "Analyse du besoin")
      end
      steps.each_with_index do |step, index|
        finished_at = steps[index + 1]&.fetch(:at) || @now
        case step[:status]
        when "In Progress"
          (1 + random.rand(3)).times do
            log_time(issue, step[:assignee], activities.fetch(profile[:activity]), step[:at], finished_at, profile, random, "Traitement")
          end
        when "Resolved"
          tester = (story[:members] - [step[:assignee]]).then { |others| others[random.rand(others.length)] }
          log_time(issue, tester, activities.fetch("Testing"), step[:at], finished_at, profile, random, "Recette") if random.rand < 0.6
        end
      end
    end

    def log_time(issue, user, activity, started_at, finished_at, profile, random, comment)
      first_day = started_at.to_date
      last_day = [finished_at.to_date, Date.current].min
      return if last_day < first_day

      TimeEntry.create!(
        project: issue.project, issue: issue, user: user, author: user, activity: activity,
        spent_on: first_day + random.rand((last_day - first_day).to_i + 1),
        hours: [(random.rand(profile[:hours]) * 4).round / 4.0, 0.25].max,
        comments: comment
      )
    end

    # Monthly steering meetings are logged on the project itself, without an issue.
    def create_follow_up_entries(subproject, definition, manager, activities)
      12.times do |month_offset|
        month = @first_month >> month_offset
        spent_on = month + 9
        next if spent_on > Date.current

        entry = TimeEntry.find_or_initialize_by(project: subproject, issue: nil, comments: "Comité de suivi #{definition[:name]} #{month.strftime('%Y-%m')}")
        entry.assign_attributes(user: manager, author: manager, activity: activities.fetch("Analysis"),
                                hours: 1.5 + (month_offset % 3) * 0.5, spent_on: spent_on)
        entry.save!
      end
    end

    def weighted(random, weights)
      target = random.rand * weights.values.sum
      weights.each do |name, weight|
        return name if (target -= weight) <= 0
      end
      weights.keys.last
    end

    def create_credit_policies(project, trackers)
      cycle_start = Date.current.beginning_of_year
      credits = CREDIT_DAYS.fetch(project.identifier)
      project.reporting_credit_policies.where.not(tracker_id: trackers.select { |tracker| credits.key?(tracker.name) }.map(&:id)).destroy_all

      trackers.each do |tracker|
        next unless credits.key?(tracker.name)

        initial_days, refill_days = credits.fetch(tracker.name)
        policy = ReportingCreditPolicy.find_or_initialize_by(project: project, tracker: tracker)
        policy.assign_attributes(
          name: tracker.name,
          initial_credit_days: initial_days,
          anniversary_month: 1,
          anniversary_day: 1,
          active_from: cycle_start,
          enabled: true
        )
        policy.save!
        policy.reporting_credit_refills.destroy_all
        next unless refill_days

        policy.reporting_credit_refills.create!(
          month: 7,
          day: 1,
          credit_days: refill_days,
          starts_on: cycle_start
        )
      end
    end
  end
end
