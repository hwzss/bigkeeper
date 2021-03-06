require 'big_keeper/util/git_operator'
require 'big_keeper/model/gitflow_type'
require 'big_keeper/model/operate_type'
require 'big_keeper/util/logger'

module BigKeeper
  # Operator for got
  class GitService
    def start(path, name, type)
      git = GitOperator.new
      branch_name = "#{GitflowType.name(type)}/#{name}"
      if !git.has_remote_branch(path, branch_name) && !git.has_local_branch(path, branch_name)
        verify_special_branch(path, 'master')
        verify_special_branch(path, 'develop')

        if !GitflowOperator.new.verify_git_flow(path)
          git.push_to_remote(path, 'develop') if !git.has_remote_branch(path, 'develop')
          git.push_to_remote(path, 'master') if !git.has_remote_branch(path, 'master')
        end
        
        GitflowOperator.new.start(path, name, type)
        git.push_to_remote(path, branch_name)
      else
        git.checkout(path, branch_name)

        if !git.has_remote_branch(path, branch_name)
          git.push_to_remote(path, branch_name)
        end
      end
    end

    def verify_special_branch(path, name)
      git = GitOperator.new

      if git.has_remote_branch(path, name)
        if git.has_local_branch(path, name)
          if git.has_commits(path, name)
            Logger.error(%Q('#{name}' has unpushed commits, you should fix it manually...))
          else
            pull(path, name)
          end
        else
          git.checkout(path, name)
        end
      end
    end

    def verify_home_branch(path, branch_name, type)
      Logger.highlight('Sync local branchs from remote, waiting...')
      git = GitOperator.new

      git.fetch(path)

      if OperateType::START == type
        if git.current_branch(path) == branch_name
          Logger.error(%(Current branch is '#{branch_name}' already. Use 'update' please))
        end
        if git.has_branch(path, branch_name)
          Logger.error(%(Branch '#{branch_name}' already exists. Use 'switch' please))
        end
      elsif OperateType::SWITCH == type
        if !git.has_branch(path, branch_name)
          Logger.error(%(Can't find a branch named '#{branch_name}'. Use 'start' please))
        end
        if git.current_branch(path) == branch_name
          Logger.error(%(Current branch is '#{branch_name}' already. Use 'update' please))
        end
      elsif OperateType::UPDATE == type
        if !git.has_branch(path, branch_name)
          Logger.error(%(Can't find a branch named '#{branch_name}'. Use 'start' please))
        end
        if git.current_branch(path) != branch_name
          Logger.error(%(Current branch is not '#{branch_name}'. Use 'switch' please))
        end
      else
        Logger.error(%(Not a valid command for '#{branch_name}'.))
      end
    end

    def branchs_with_type(path, type)
      branchs = []
      Dir.chdir(path) do
        IO.popen('git branch -a') do |io|
          io.each do |line|
            branchs << line.rstrip if line =~ /(\* |  )#{GitflowType.name(type)}*/
          end
        end
      end
      branchs
    end

    def pull(path, branch_name)
      git = GitOperator.new
      if git.current_branch(path) == branch_name
        git.pull(path)
      else
        Dir.chdir(path) do
          `git pull origin #{branch_name}:#{branch_name}`
        end
      end
    end

    def verify_push(path, comment, branch_name, name)
      git = GitOperator.new
      if git.has_changes(path)
        git.commit(path, comment)
        if git.has_remote_branch(path, branch_name)
          Dir.chdir(path) do
            `git push`
          end
        else
          git.push_to_remote(path, branch_name)
        end
      else
        Logger.default("Nothing to push for '#{name}'.")
      end
    end

    def verify_rebase(path, branch_name, name)
      Dir.chdir(path) do
        IO.popen("git rebase #{branch_name} --ignore-whitespace") do |io|
          unless io.gets
            Logger.error("#{name} is already in a rebase-apply, Please:\n\
                  1.Resolve it;\n\
                  2.Commit the changes;\n\
                  3.Push to remote;\n\
                  4.Create a MR;\n\
                  5.Run 'finish' again.")
          end
          io.each do |line|
            next unless line.include? 'Merge conflict'
            Logger.error("Merge conflict in #{name}, Please:\n\
                  1.Resolve it;\n\
                  2.Commit the changes;\n\
                  3.Push to remote;\n\
                  4.Create a MR;\n\
                  5.Run 'finish' again.")
          end
        end
        `git push -f origin #{branch_name}`
        GitOperator.new.checkout(path, 'develop')
      end
    end
  end
end
