defmodule Aelita2.GitHub.Integration do
  @moduledoc """
  Wrappers for accessing the GitHub Integration API.
  """

  @content_type "application/vnd.github.machine-man-preview+json"

  # Get a repository by ID:
  # https://api.github.com/repositories/59789129

  # Public API

  def config do
    :aelita2
    |> Application.get_env(Aelita2.GitHub.Integration)
    |> Keyword.merge(Application.get_env(:aelita2, Aelita2.GitHub))
    |> Keyword.merge([site: "https://api.github.com"])
  end

  def get_installation_token!(installation_xref) do
    import Joken
    cfg = config()
    pem = JOSE.JWK.from_pem(cfg[:pem])
    jwt_token = %{
      iat: current_time(),
      exp: current_time() + 400,
      iss: cfg[:iss]}
    |> token()
    |> sign(rs256(pem))
    |> get_compact()
    %{body: raw, status_code: 201} = HTTPoison.post!(
      "#{cfg[:site]}/installations/#{installation_xref}/access_tokens",
      "",
      [{"Authorization", "Bearer #{jwt_token}"}, {"Accept", @content_type}])
    Poison.decode!(raw)["token"]
  end

  def get_my_repos!(token, url \\ nil, append \\ []) when is_binary(token) do
    {url, params} = case url do
      nil ->
        {"#{config()[:site]}/installation/repos", []}
      url ->
        params = URI.parse(url).query |> URI.query_decoder() |> Enum.to_list()
        {url, [params: params]}
    end
    %{body: raw, status_code: 200, headers: headers} = HTTPoison.get!(
      url,
      [{"Authorization", "token #{token}"}, {"Accept", @content_type}],
      params)
    repositories = Poison.decode!(raw)["repositories"]
    |> Enum.map(&%{
      id: &1["id"],
      name: &1["full_name"],
      permissions: %{
        admin: &1["permissions"]["admin"],
        push: &1["permissions"]["push"],
        pull: &1["permissions"]["pull"]
      },
      owner: %{
        id: &1["owner"]["id"],
        login: &1["owner"]["login"],
        avatar_url: &1["owner"]["avatar_url"],
        type: &1["owner"]["type"]}})
    |> Enum.concat(append)
    next_headers = headers
    |> Enum.filter(&(elem(&1, 0) == "Link"))
    |> Enum.map(&(ExLinkHeader.parse!(elem(&1, 1))))
    |> Enum.filter(&!is_nil(&1.next))
    case next_headers do
      [] -> repositories
      [next] -> get_my_repos!(token, next.next.url, repositories)
    end
  end
end