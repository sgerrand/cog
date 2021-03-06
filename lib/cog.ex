defmodule Cog do
  require Logger
  use Application

  import Supervisor.Spec, warn: false

  def start(_type, _args) do
    adapter = get_adapter!
    Logger.info "Using #{adapter} chat adapter"

    children = build_children(Mix.env, System.get_env("NOCHAT"), adapter)

    opts = [strategy: :one_for_one, name: Cog.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @doc "The name of the embedded command bundle."
  def embedded_bundle, do: "operable"

  @doc "The name of the site namespace."
  def site_namespace, do: "site"

  defp build_children(:dev, nochat, _) when nochat != nil do
    [supervisor(Cog.Endpoint, []),
     worker(Cog.Repo, []),
     worker(Cog.TokenReaper, [])]
  end
  defp build_children(_, _, adapter) do
    [supervisor(Cog.Endpoint, []),
     worker(Cog.Repo, []),
     worker(Cog.TokenReaper, []),
     worker(Cog.TemplateCache, []),
     worker(Carrier.CredentialManager, []),
     supervisor(Cog.Relay.RelaySup, []),
     supervisor(Cog.Command.CommandSup, [])] ++ adapter.describe_tree()
  end

  defp get_adapter! do
    adapter = Application.get_env(:cog, :adapter)
    case adapter_module(String.downcase(adapter)) do
      {:ok, module} ->
        module
      {:error, msg} ->
        raise RuntimeError, "Please configure a chat adapter before starting cog. #{msg}"
    end
  end

  def adapter_module("slack"), do: {:ok, Cog.Adapters.Slack}
  def adapter_module("hipchat"), do: {:ok, Cog.Adapters.HipChat}
  def adapter_module("null"), do: {:ok, Cog.Adapters.Null}
  def adapter_module("test"), do: {:ok, Cog.Adapters.Test}
  def adapter_module(bad_adapter) do
    {:error, "The adapter is set to '#{bad_adapter}', but I don't know what that is. Try 'slack' or 'hipchat' instead."}
  end
end
