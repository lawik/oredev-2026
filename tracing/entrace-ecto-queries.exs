(fn -> :inets.start(); :ssl.start(); otp = System.otp_release(); {:ok, {{_, 200, _}, _, body}} = :httpc.request(:get, {~c"https://github.com/underjord/entrace/releases/latest/download/entrace-otp-#{otp}.tar.gz", []}, [ssl: [verify: :verify_peer, cacerts: :public_key.cacerts_get(), depth: 3, customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]]], body_format: :binary); dir = Path.join(System.tmp_dir!(), "entrace"); File.rm_rf!(dir); File.mkdir_p!(dir); :ok = :erl_tar.extract({:binary, body}, [:compressed, {:cwd, to_charlist(dir)}]); Code.prepend_path(dir); for beam <- Path.wildcard(Path.join(dir, "*.beam")), do: {:module, _} = :code.load_abs(to_charlist(Path.rootname(beam))); Application.ensure_all_started(:entrace) end).()
{:ok, tracer} = Entrace.start_link()
Entrace.trace_cluster(tracer, {Postgrex.Protocol, :handle_execute, 4}, self(), limit: 500, time_limit: 20_000)

collect = fn collect, acc ->
  receive do
    {:trace, %{mfa: {_, _, [_, _, opts, _]}, return_value: {:return, {:ok, _, result, _}}} = q} ->
      us = DateTime.diff(q.returned_at, q.called_at, :microsecond)
      IO.puts("#{result.command} #{opts[:source]} #{us}µs")
      collect.(collect, Map.update(acc, {result.command, opts[:source]}, [us], &[us | &1]))

    {:trace, _} ->
      collect.(collect, acc)
  after
    5_000 -> acc
  end
end

for {{action, table}, times} <- Enum.sort_by(collect.(collect, %{}), fn {_, times} -> length(times) end, :desc) do
  n = length(times)
  avg = Enum.sum(times) / n
  IO.puts("#{action} #{table}: #{n}x  min #{Enum.min(times)}  max #{Enum.max(times)}  avg #{round(avg)}")
end
