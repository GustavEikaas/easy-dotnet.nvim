# Getting started

This briefly describe one way to getting started using easy-dotnet on the windows platform

## Installing Neovim + extras

We use chocolatey as the package manager. To get up and running we need a few tools on top of neovim itself. a C-compiler and ripgrep. Also .net of course

```
> choco install neovim
> choco install ripgrep
> choco install choco 
> choco install dotnet-8.0-sdk
> choco install git
> choco install fzf
```

## Starting neovim
you should now open a new terminal and start neovim

```
> nvim 
```


## Installing neovim plugin manager

first we need to create the folder for the config file (we use powershell). Then we start neovim to configure

``` 
> 
> mkdir $env:LOCALAPPDATA\nvim\
> nvim $env:LOCALAPPDATA\nvim\init.lua
```

Starting neovim is an underwhelming surprise the first time. Let's change that. Add the following to `init.lua`

```
-- Set <space> as the leader key
--  NOTE: Must happen before plugins are loaded (otherwise wrong leader will be used)vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

-- Set to true if you have a Nerd Font installed and selected in the terminal
vim.g.have_nerd_font = false

vim.opt.number = true

-- Enable mouse mode, can be useful for resizing splits for example!
vim.opt.mouse = 'a'

-- add this if you want to be able to copy from neovim to windows programs
vim.schedule(function() vim.opt.clipboard = 'unnamedplus' end)
```

Restarting neovim you will see you have line numbers



## Setting up a plugin manager

There are many ways of installing plugins into neovim. We use lazy.nvim here. 
Add this to `init.lua`. It will use git to clone the plugin manager into your plugin directory and from there install a few plugins.

```
-- Install lazy.nvim if missing
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
    vim.fn.system({
        "git",
        "clone",
        "--filter=blob:none",
        "https://github.com/folke/lazy.nvim.git",
        "--branch=stable", -- latest stable release
        lazypath,
    })
end
vim.opt.rtp:prepend(lazypath)

-- install plugins using lazy.nvim
require("lazy").setup({
    -- Example plugins
    {
        "nvim-treesitter/nvim-treesitter",
        run = ":TSUpdate",
    },
    {
        "folke/tokyonight.nvim",
    },
})
```

Close nvim by typing `:wqa` and <enter>. Reopen nvim, if we were succesfull, you will see new colors in the editor (from `tokyonight.nvim`).



## Install the Roslyn LSP

An LSP is pretty much required. Either omnisharp or roslyn. My recommendation is roslyn because it is a very good plugin. We should link to the repo and refer to the setup section of the readme.

in `init.lua` add at the bottom

```
{
    "seblj/roslyn.nvim",
    ft = "cs",
    opts = {
        -- your configuration comes here; leave empty for default settings
    }
}
```

The configuration is elaborate. You should read ore at https://github.com/seblj/roslyn.nvim


## Install the easy-dotnet plugin

Finally, it's time to install the plugin that enable us to do .net development in neovim.

in `init.lua` add at the bottom

```
{
  "GustavEikaas/easy-dotnet.nvim",
  dependencies = { "nvim-lua/plenary.nvim", 'nvim-telescope/telescope.nvim', },
  config = function()
    require("easy-dotnet").setup()
  end
}
```



## Compiling and running hello world


