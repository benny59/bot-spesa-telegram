# frozen_string_literal: true

require "cgi"
require "base64"
require_relative "lista_pdf"

# Lista della spesa come pagina HTML autosufficiente (un solo file, immagini incluse):
# stesso taglio del PDF (/pdf) ma le caselle si spuntano in qualsiasi browser, anche
# senza rete. Pensata per essere inviata a un amico che fa la spesa al posto nostro.
module ListaHtml
  MINIATURA_PX = 220

  # Ritorna l'HTML (String) o nil se non c'è nulla da comprare.
  def self.genera(bot, g_id, t_id, user_id: nil)
    items = ListaPdf.articoli_da_comprare(g_id, t_id, user_id: user_id)
    return nil if items.empty?

    info = DataManager.recupera_nomi_contesto(g_id.to_i, t_id.to_i)
    sezioni = ListaPdf.raggruppa(items, g_id, t_id)
    tmp = []
    oggi = Time.now
    chiave = "spesa-#{g_id}-#{t_id}-#{oggi.strftime('%Y%m%d')}-#{items.map { |i| i['id'] }.sum}"

    corpo = sezioni.map do |categoria, articoli|
      righe = articoli.map { |art| riga(bot, art, tmp) }.join("\n")
      nome = categoria.empty? ? "Altro" : categoria
      %(<section><h2>#{esc(nome)}</h2>\n<ul>\n#{righe}\n</ul></section>)
    end.join("\n")

    sotto = [info[:nome], ["Generale", "Lista Personale", ""].include?(info[:topic].to_s) ? nil : info[:topic]].compact.join(" · ")
    pagina(titolo: "Lista della spesa", sotto: sotto,
           data: oggi.strftime("%d/%m/%Y"), totale: items.size, corpo: corpo, chiave: chiave)
  ensure
    tmp&.each { |f| File.delete(f) if File.exist?(f) }
  end

  # ---------------------------------------------------------------------------
  def self.esc(s) = CGI.escapeHTML(s.to_s)

  def self.riga(bot, art, tmp)
    nome = PhotoAlbum.nome_pulito(art, art["gruppo_id"], art["topic_id"])
    link = ListaPdf.link_articolo(art)
    link = link.to_s.dup.force_encoding("UTF-8") if link # ByteString (ASCII) -> String

    foto = ListaPdf.prima_foto(bot, art, tmp, lato: MINIATURA_PX, qualita: 70, soglia: 25_000)
    img = if foto
        b64 = Base64.strict_encode64(File.binread(foto))
        %(<img src="data:image/jpeg;base64,#{b64}" alt="" loading="lazy">)
      else
        ""
      end
    testo = esc(nome)
    testo = %(<a href="#{esc(link)}" target="_blank" rel="noopener">#{testo}</a>) if link
    <<~HTML.chomp
      <li><label><input type="checkbox" data-id="#{art['id'].to_i}"><span class="foto">#{img}</span><span class="nome">#{testo}</span></label></li>
    HTML
  end

  def self.pagina(titolo:, sotto:, data:, totale:, corpo:, chiave:)
    <<~HTML
      <!doctype html>
      <html lang="it">
      <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>#{esc(titolo)}</title>
      <style>
        :root { --fg:#111; --bg:#fff; --muted:#777; --linea:#e3e3e3; --link:#1a4fa0; --ok:#2e7d32; }
        @media (prefers-color-scheme: dark) { :root { --fg:#eee; --bg:#151515; --muted:#999; --linea:#333; --link:#8ab4f8; --ok:#81c784; } }
        * { box-sizing: border-box; }
        body { margin:0; background:var(--bg); color:var(--fg); font:16px/1.35 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif; }
        main { max-width:176mm; margin:0 auto; padding:16px; }
        h1 { margin:0; font-size:1.6rem; }
        .sotto { color:var(--muted); font-size:.95rem; }
        .meta { color:var(--muted); font-size:.8rem; }
        header { border-bottom:2px solid var(--fg); padding-bottom:8px; margin-bottom:6px; }
        .progresso { position:sticky; top:0; background:var(--bg); padding:6px 0; font-size:.85rem; color:var(--muted); border-bottom:1px solid var(--linea); }
        h2 { margin:18px 0 4px; font-size:.75rem; letter-spacing:.12em; text-transform:uppercase; color:var(--muted); border-bottom:1px solid var(--linea); padding-bottom:3px; }
        ul { list-style:none; margin:0; padding:0; }
        li { border-bottom:1px solid var(--linea); }
        label { display:flex; align-items:center; gap:12px; min-height:56px; padding:6px 0; cursor:pointer; }
        input[type=checkbox] { flex:none; width:26px; height:26px; accent-color:var(--ok); }
        .foto { flex:none; width:56px; height:56px; display:flex; align-items:center; justify-content:center; }
        .foto img { max-width:56px; max-height:56px; border-radius:4px; }
        .nome { font-weight:700; font-size:1.05rem; }
        .nome a { color:var(--link); text-decoration:none; }
        .nome a:hover { text-decoration:underline; }
        li.preso .nome, li.preso .foto { opacity:.4; }
        li.preso .nome { text-decoration:line-through; }
        footer { margin-top:20px; color:var(--muted); font-size:.75rem; text-align:center; }
        @media print {
          @page { size: B5; margin: 12mm; }
          :root { --fg:#000; --bg:#fff; --muted:#555; --linea:#ccc; --link:#1a4fa0; }
          .progresso { display:none; }
          main { padding:0; max-width:none; }
          li { break-inside:avoid; }
          li.preso .nome, li.preso .foto { opacity:1; text-decoration:none; }
          input[type=checkbox] { appearance:none; -webkit-appearance:none; width:5mm; height:5mm; border:.3mm solid #000; }
        }
      </style>
      </head>
      <body>
      <main>
        <header>
          <h1>#{esc(titolo)}</h1>
          #{sotto.empty? ? "" : %(<div class="sotto">#{esc(sotto)}</div>)}
          <div class="meta">#{esc(data)} · #{totale} #{totale == 1 ? 'articolo' : 'articoli'}</div>
        </header>
        <div class="progresso" id="progresso"></div>
      #{corpo}
        <footer>Tocca la casella per segnare l'articolo come preso.</footer>
      </main>
      <script>
      (function () {
        var KEY = #{chiave.to_json};
        var boxes = Array.prototype.slice.call(document.querySelectorAll('input[type=checkbox]'));
        var stato = {};
        try { stato = JSON.parse(localStorage.getItem(KEY) || '{}'); } catch (e) {}
        function aggiorna() {
          var presi = 0;
          boxes.forEach(function (b) {
            b.closest('li').classList.toggle('preso', b.checked);
            if (b.checked) presi++;
          });
          document.getElementById('progresso').textContent = presi + ' di ' + boxes.length + ' presi' + (presi === boxes.length ? ' \\u2713' : '');
        }
        boxes.forEach(function (b) {
          b.checked = !!stato[b.dataset.id];
          b.addEventListener('change', function () {
            stato[b.dataset.id] = b.checked ? 1 : 0;
            try { localStorage.setItem(KEY, JSON.stringify(stato)); } catch (e) {}
            aggiorna();
          });
        });
        aggiorna();
      })();
      </script>
      </body>
      </html>
    HTML
  end
end
