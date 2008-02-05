[% BLOCK menuitem -%]
  [&nbsp;[% prefix -%]
  [%- IF url -%]
    <a [% 'title="' _ title _ '"' IF title %] href="[% url %]">[% name %]</a>
  [%- ELSE -%]
   <strong>[% name %]</strong>
  [%- END -%]
  &nbsp;]
[%- END -%]
[% BLOCK marker %] [<strong class="pmarker">[% text %]</strong>] [%- END %]
