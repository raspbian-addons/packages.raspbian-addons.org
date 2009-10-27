[% BLOCK menuitem -%]
  [&nbsp;[% prefix -%]
  [%- IF url -%]
    <a [% 'title="' _ title _ '"' IF title %] href="[% url %]">[% name %]</a>
  [%- ELSE -%]
   <strong>[% name %]</strong>
  [%- END -%]
  &nbsp;]
[%- END -%]
[% BLOCK marker %] [[% IF url %]<a href="[% url %]">[% END %]<strong class="pmarker" [% 'title="' _ title _ '"' IF title %]>[% text %]</strong>[% IF url %]</a>[% END %]] [%- END %]
[%- BLOCK desc_i18n;
   IF trans_desc.$ddtp_lang;
      trans_desc.$ddtp_lang | html;
   ELSIF trans_desc.$po_lang;
      trans_desc.$po_lang | html;
   ELSE;
      desc | html;
   END;
END -%]
[%- BLOCK desc_i18n_dd;
   IF trans_desc.$ddtp_lang;
      '<dd lang="' _ ddtp_lang _ '">';
      trans_desc.$ddtp_lang | html;
   ELSIF trans_desc.$po_lang;
      '<dd>';
      trans_desc.$po_lang | html;
   ELSE;
      '<dd lang="en">';
      desc | html;
   END;
   '</dd>' UNLESS no_end_tag;
END -%]
