#!/home/carson/.rvm/rubies/ruby-2.6.2/bin/ruby -w

require 'octokit'
require 'csv'

# =====================================================================
#  github setup
# =====================================================================
git_token = ENV["GITHUB_TOKEN"]
unless git_token
  throw "You must set the GITHUB_TOKEN environment variable"
end
client = Octokit::Client.new(:access_token => git_token)
client.auto_paginate = true
user = client.user
git_username = user.login
class_repo_name = "msu/csci-440-fall2020"
class_repo_url = "https://github.com/#{class_repo_name}"
puts("github user id: #{user.login}")

# =====================================================================
#  helper functions
# =====================================================================
def for_each_student_dir
  each_student do |student|
    dir = "repos/#{student_dir(student)}"
    if Dir.exist? dir
      Dir.chdir dir do
        yield student["FIRST_NAME"], student["LAST_NAME"], dir
      end
    else
      puts "Directory #{dir} does not exist"
    end
  end
end

def each_student
  results = CSV.read("students.csv", headers: true)
  results.each do |row|
    yield row
  end
end

def student_dir(student)
  student["FIRST_NAME"].downcase + "_" + student["LAST_NAME"].downcase
end

def maven_test(pattern, output_file)
  puts `timeout 30 mvn -B "-Dtest=#{pattern}" test > #{output_file} 2> err.out`
end

def cmake(output_file)
  puts `timeout 30 cmake . > tmp.out; make > #{output_file} 2> err.out;`
end

def maybe_exec(command, output_file)
  begin
    output = `#{command}`
    File.open(output_file, 'w') do |file|
      file.write output
    end
  rescue
    puts "Could not execute #{command}"
  end
end

def pull
  puts `git pull`
end

def push_grading
  puts `git add grading/*; git commit -m "From Autograder"; git push`
end

def grading_dir_exist?
  Dir.exist? "grading"
end

def make_grading_dir
  Dir.mkdir "grading" unless Dir.exist? "grading"
end


# =====================================================================
#  command line
# =====================================================================

case ARGV[0]
when "accept_invites"
  puts("Accepting Repository Invites")
  puts("------------------")
  client.user_repository_invitations.each do |ri|
    puts "  Accepting #{ri[:id]}: #{ri[:repository][:full_name]}"
    client.accept_repo_invitation(ri[:id])
  end
when "grade"
  assignment = ARGV[1]
  if assignment == "tokenizing"
    for_each_student_dir do |first, last, dir|
      puts "Grading #{first} #{last} in #{dir}"
      pull
      if grading_dir_exist?
        maven_test("CatScriptTokenizerTest", "grading/tokenizer_test.txt")
        push_grading
      end
    end
  elsif assignment == "expressions"
    for_each_student_dir do |first, last, dir|
      puts "Grading #{first} #{last} in #{dir}"
      pull
      if grading_dir_exist?
        maven_test("CatscriptParserExpressionsTest", "grading/expressions_test.txt")
        push_grading
      end
    end
  elsif assignment == "eval"
    for_each_student_dir do |first, last, dir|
      puts "Grading #{first} #{last} in #{dir}"
      pull
      if grading_dir_exist?
        maven_test("edu.montana.csci.csci468.tokenizer.*Test,edu.montana.csci.csci468.parser.*Test,edu.montana.csci.csci468.eval.*Test", "grading/eval_test.txt")
        push_grading
      end
    end
  elsif assignment == "capstone"
    for_each_student_dir do |first, last, dir|
      if grading_dir_exist?
        pull
        source_exists = File.exist? "capstone/portfolio/source.zip"
        pdf_exists = File.exist?("capstone/portfolio/#{first}_#{last}_portfolio.pdf") ||
                                     File.exist?("capstone/portfolio/#{first.downcase}_#{last.downcase}_portfolio.pdf")||
                                     File.exist?("capstone/portfolio/#{first.downcase}_#{last.downcase}_Portfolio.pdf")
        if source_exists and pdf_exists
          str = 'All Good'
        else
          str = "Errors:\n\n"
          unless source_exists
            str = str + "- Missing source zip\n"
          end
          unless pdf_exists
            str = str + "- Missing #{first.downcase}_#{last.downcase}_portfolio.pdf\n"
          end
        end
        puts "\n\nResults for #{first} #{last}: \n#{str}"
        File.write('grading/capstone.txt', str, mode: 'w')
        push_grading
      end
    end
  elsif assignment == "capstone_check"
    for_each_student_dir do |first, last, dir|
      if grading_dir_exist?
        source_exists = File.exist? "capstone/portfolio/source.zip"
        pdf_exists = File.exist?("capstone/portfolio/#{first}_#{last}_portfolio.pdf") ||
                                     File.exist?("capstone/portfolio/#{first.downcase}_#{last.downcase}_portfolio.pdf")||
            File.exist?("capstone/portfolio/#{first.downcase}_#{last.downcase}_Portfolio.pdf")

        unless source_exists and pdf_exists
          str = ""
          unless source_exists
            str = str + " Missing source zip, "
          end
          unless pdf_exists
            str = str + " Missing #{first.downcase}_#{last.downcase}_portfolio.pdf"
          end
          puts "#{first} #{last}-"
          puts `ls ./capstone/portfolio`.split("\n").map {|x| "  " + x }
          puts "\n"
        end
      end
    end
  elsif assignment == "all"
    for_each_student_dir do |first, last, dir|
      puts "Grading #{first} #{last} in #{dir}"
      pull
      if grading_dir_exist?
        maven_test("edu.montana.csci.csci468.bytecode.*Test", "grading/bytecode.txt")
        maven_test("edu.montana.csci.csci468.tokenizer.*Test,edu.montana.csci.csci468.parser.*Test,edu.montana.csci.csci468.eval.*Test", "grading/rest.txt")
        push_grading
      end
    end
  else
    puts "Unknown assignment: #{assignment}"
  end
when "clone_repos"
  each_student do |student|
    student_dir = student_dir(student)
    if Dir.exist? student_dir
      puts "Directory #{student_dir} already exists, skipping..."
    else
      repo_url = student["REPO"]&.gsub("https://", "")
      if repo_url.nil? || repo_url.strip.empty?
        puts("No git URL for #{student["FIRST_NAME"]} #{student["LAST_NAME"]}")
        next
      end
      `git clone https://#{git_username}:#{git_token}@#{repo_url} repos/#{student_dir} --branch master`
    end
  end
when "clear_repos"
  `rm -rf repos/*`
when "print_grades"
  puts `find repos/ | grep '#{ARGV[1]}'| xargs grep 'Tests run:' | tac | sort -u -t: -k1,1`
when "names"
  each_student do |student|
    puts student["FIRST_NAME"]+ " " + student["LAST_NAME"]
  end
when "pull"
  for_each_student_dir do |student|
    pull
  end
else
  puts "Commands:
    accept_invites - accepts pending invites
    clone_repos - clones student repos to the repos directory
    clear_repos - removes all repos from the current dir
    grade <assignment> - grades the given assignment and pushes it"
end
