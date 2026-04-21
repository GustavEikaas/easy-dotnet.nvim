Hello,

Thank you for raising an issue. If the issue is a bug please do the following

1. Open neovim  
2. Run `:checkhealth easy-dotnet`  
3. Paste the result in your issue  

This makes it a lot easier for me to debug because a lot of the times it's important for me to see OS info, server version, plugin version, etc.. Thank you for understanding

### Tip: capturing server logs

If the bug involves a crash, an unexpected error, or something the server is (or isn't) doing, server logs are gold:

1. `:Dotnet _server loglevel verbose` — turn on verbose logging on the running server (also propagates to the BuildServer)
2. Reproduce the issue
3. `:Dotnet _server logdump` — opens the IDE server's in-memory log ring
4. `:Dotnet _server logdump buildserver` — opens the BuildServer's log ring (relevant for build, restore, and project-evaluation bugs)

Paste the relevant output into the issue. The default log level is `off` (only exceptions are kept), so without step 1 you probably won't see much.
