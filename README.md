# boomi-git
Populate git from AtomSphere API

## Instructions
1. Have a access to an AtomSphere account. https://train.boomi.com is a great place to start.
2. Install git command-line https://git-scm.com/downloads)
3. Get the script: (```git clone https://github.com/richard087/boomi-git.git``` will work).
4. Setup API token authentication for your Boomi account: https://help.boomi.com/bundle/integration/page/int-AtomSphere_API_Tokens_page.html
5. Keep/get your API token handy. You'll need to use it as your password when you run the script.
6. Script can be executed:
`powershell -ExecutionPolicy Bypass -file .\boomi-git.ps1 --accountId <AtomShphere account to access> --ApiUser BOOMI_TOKEN.<Boomi login email address> --repo_path <path for new git repo>`

For example: `powershell -ExecutionPolicy Bypass -file .\boomi-git.ps1 --accountId trainingmredthehorse-ABC12D --ApiUser BOOMI_TOKEN.wilbur@mr-ed.com --repo_path C:\Users\Wilbur\Documents\boomi-history`

7. You'll be asked for a password, enter your API token, from step 4.
8. There's not much output. Initially, you'll just see this:
```
Initialized empty Git repository in C:/Users/Wilbur/Documents/boomi-history/.git/
0.00488092666666667
0.254000553333333
```
The numbers are timestamps from the early stages of the process. The next output won't be for some minutes, while the script fetches the contents of the AtomSphere repository. This takes anything from 5 minutes to ... a long time. Eventually, the contents will be retrieved and the AtomSphere changes will be turned into git conmmits and you can watch them fly past as the git repo is built.

