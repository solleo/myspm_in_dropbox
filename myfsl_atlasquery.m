function [strc, strc_all]=myfsl_atlasquery(mni_xyz, ijkflag)
% [strc, strc_all]=myfsl_atlasquery(mni_xyz, ijkflag)
% mni_xyz: MNI-coordinates (mm) or 1-based ijk (voxels) with nifti
%
% with no input arguments, will try to read a coordinate from SPM figure.
%
% (cc) 2015. sgKIM. solleo@gmail.com

if ~exist('ijkflag','var')
  ijkflag=0;
end

fslpath = getenv('FSLDIR');
xmlFNAMES{1}=fullfile(fslpath,'data/atlases/HarvardOxford-Cortical-Lateralized.xml');
niiFNAMES{1}=fullfile(fslpath,'data/atlases/HarvardOxford/HarvardOxford-cortl-prob-1mm.nii.gz');
xmlFNAMES{2}=fullfile(fslpath,'data/atlases/HarvardOxford-Subcortical.xml');
niiFNAMES{2}=fullfile(fslpath,'data/atlases/HarvardOxford/HarvardOxford-sub-prob-1mm.nii.gz');
xmlFNAMES{3}=fullfile(fslpath,'data/atlases/Cerebellum_MNIfnirt.xml');
niiFNAMES{3}=fullfile(fslpath,'data/atlases/Cerebellum/Cerebellum-MNIfnirt-prob-1mm.nii.gz');
xmlFNAMES{4}=fullfile(fslpath,'data/atlases/JHU-tracts.xml');
niiFNAMES{4}=fullfile(fslpath,'data/atlases/JHU/JHU-ICBM-tracts-prob-1mm.nii.gz');

% okay unzipping takes more than 2 sec..., so try to find it from /tmp first
for a=1:4
  [~,fname1,ext1]=fileparts(niiFNAMES{a});
  if ~exist(['/tmp/',fname1], 'file')
    gunzip(niiFNAMES{a}, '/tmp/');
  end
  niiFNAMES{a} = ['/tmp/',fname1];
  xDOC{a}=xml2struct(xmlFNAMES{a});
end

%%
% get ijk coordinate

if ~ijkflag
  if nargin == 0
    hReg= evalin('base','hReg;');
    xSPM= evalin('base','xSPM;');
    if numel(hReg) == 1
      xyz = spm_XYZreg('GetCoords',hReg);
    else
      xyz = hReg;
    end
  else
    xyz = mni_xyz';
  end
  try xSPM.XYZmm
    [xyz,i] = spm_XYZreg('NearestXYZ', xyz ,xSPM.XYZmm);
  catch ME
    xyz = mni_xyz';
  end
  ijk = round(xyz2ijk(xyz, niiFNAMES{1}))';
else
  ijk = mni_xyz';
  xyz = round(ijk2xyz(ijk', niiFNAMES{1}))';
end


%% now read probs for XYZ using spm_get_data (very efficient when reading only one voxel)
strc.name='N/A';
strc.prob=0;
strc_all.name=cell(1,4);
strc_all.prob=[0 0 0 0];
k=1;
for a=1:4 % for each atlas
  P = spm_vol(niiFNAMES{a});
  probs = spm_get_data(P, ijk);
  if a==2
    % ignore cerebral grey/white matter in the subcortical atlas
    probs([1 2 12 13],:)=0;
  end
  
  % find maximal prob from 
  if size(ijk,2) == 1 % this works for probs<Nx1>
    [~,b]=max(probs);  
    probs_b = probs(b);
  else % in case of cluster.. probs<NxV>
    % I want to compute mean prob for each label
    probs_ri = round(mean(probs,2));
    [~,b]=max(probs_ri);
    probs_b = probs_ri(b);
  end
  
  if probs_b > strc.prob % is the current maximal greater than the previous one?
    strc.name = xDOC{a}.atlas.data.label{b}.Text;
    strc.prob = probs_b;
  end
  
  % for any other possibilities...
  
  if size(ijk,2) == 1 % for a voxel
    nz = find(~~probs); % non-zero probs.
    for j=1:numel(nz)
      strc_all.name{k}=xDOC{a}.atlas.data.label{nz(j)}.Text;
      strc_all.prob(k)=probs(nz(j));
      k=k+1;
    end
  else % for a cluster
    nz = find(~~probs_ri);
    for j=1:numel(nz)
      strc_all.name{k}=xDOC{a}.atlas.data.label{nz(j)}.Text;
      strc_all.prob(k)=probs_ri(nz(j));
      k=k+1;
    end
  end
end

strc_unsort=strc_all;
% and sort;
[~,idx] = sort(strc_unsort.prob, 'descend');
for j=1:numel(idx)
  strc_all.name{j} = strc_unsort.name{idx(j)};
  strc_all.prob(j) = strc_unsort.prob(idx(j));
end

end


%% =============================================================================
% source: http://www.mathworks.com/matlabcentral/fileexchange/28518-xml2struct

function [ s ] = xml2struct( file )
%Convert xml file into a MATLAB structure
% [ s ] = xml2struct( file )
%
% A file containing:
% <XMLname attrib1="Some value">
%   <Element>Some text</Element>
%   <DifferentElement attrib2="2">Some more text</Element>
%   <DifferentElement attrib3="2" attrib4="1">Even more text</DifferentElement>
% </XMLname>
%
% Will produce:
% s.XMLname.Attributes.attrib1 = "Some value";
% s.XMLname.Element.Text = "Some text";
% s.XMLname.DifferentElement{1}.Attributes.attrib2 = "2";
% s.XMLname.DifferentElement{1}.Text = "Some more text";
% s.XMLname.DifferentElement{2}.Attributes.attrib3 = "2";
% s.XMLname.DifferentElement{2}.Attributes.attrib4 = "1";
% s.XMLname.DifferentElement{2}.Text = "Even more text";
%
% Please note that the following characters are substituted
% '-' by '_dash_', ':' by '_colon_' and '.' by '_dot_'
%
% Written by W. Falkena, ASTI, TUDelft, 21-08-2010
% Attribute parsing speed increased by 40% by A. Wanner, 14-6-2011
% Added CDATA support by I. Smirnov, 20-3-2012
%
% Modified by X. Mo, University of Wisconsin, 12-5-2012

    if (nargin < 1)
        clc;
        help xml2struct
        return
    end
    
    if isa(file, 'org.apache.xerces.dom.DeferredDocumentImpl') || isa(file, 'org.apache.xerces.dom.DeferredElementImpl')
        % input is a java xml object
        xDoc = file;
    else
        %check for existance
        if (exist(file,'file') == 0)
            %Perhaps the xml extension was omitted from the file name. Add the
            %extension and try again.
            if (isempty(strfind(file,'.xml')))
                file = [file '.xml'];
            end
            
            if (exist(file,'file') == 0)
                error(['The file ' file ' could not be found']);
            end
        end
        %read the xml file
        xDoc = xmlread(file);
    end
    
    %parse xDoc into a MATLAB structure
    s = parseChildNodes(xDoc);
    
end

% ----- Subfunction parseChildNodes -----
function [children,ptext,textflag] = parseChildNodes(theNode)
    % Recurse over node children.
    children = struct;
    ptext = struct; textflag = 'Text';
    if hasChildNodes(theNode)
        childNodes = getChildNodes(theNode);
        numChildNodes = getLength(childNodes);

        for count = 1:numChildNodes
            theChild = item(childNodes,count-1);
            [text,name,attr,childs,textflag] = getNodeData(theChild);
            
            if (~strcmp(name,'#text') && ~strcmp(name,'#comment') && ~strcmp(name,'#cdata_dash_section'))
                %XML allows the same elements to be defined multiple times,
                %put each in a different cell
                if (isfield(children,name))
                    if (~iscell(children.(name)))
                        %put existsing element into cell format
                        children.(name) = {children.(name)};
                    end
                    index = length(children.(name))+1;
                    %add new element
                    children.(name){index} = childs;
                    if(~isempty(fieldnames(text)))
                        children.(name){index} = text; 
                    end
                    if(~isempty(attr)) 
                        children.(name){index}.('Attributes') = attr; 
                    end
                else
                    %add previously unknown (new) element to the structure
                    children.(name) = childs;
                    if(~isempty(text) && ~isempty(fieldnames(text)))
                        children.(name) = text; 
                    end
                    if(~isempty(attr)) 
                        children.(name).('Attributes') = attr; 
                    end
                end
            else
                ptextflag = 'Text';
                if (strcmp(name, '#cdata_dash_section'))
                    ptextflag = 'CDATA';
                elseif (strcmp(name, '#comment'))
                    ptextflag = 'Comment';
                end
                
                %this is the text in an element (i.e., the parentNode) 
                if (~isempty(regexprep(text.(textflag),'[\s]*','')))
                    if (~isfield(ptext,ptextflag) || isempty(ptext.(ptextflag)))
                        ptext.(ptextflag) = text.(textflag);
                    else
                        %what to do when element data is as follows:
                        %<element>Text <!--Comment--> More text</element>
                        
                        %put the text in different cells:
                        % if (~iscell(ptext)) ptext = {ptext}; end
                        % ptext{length(ptext)+1} = text;
                        
                        %just append the text
                        ptext.(ptextflag) = [ptext.(ptextflag) text.(textflag)];
                    end
                end
            end
            
        end
    end
end

% ----- Subfunction getNodeData -----
function [text,name,attr,childs,textflag] = getNodeData(theNode)
    % Create structure of node info.
    
    %make sure name is allowed as structure name
    name = toCharArray(getNodeName(theNode))';
    name = strrep(name, '-', '_dash_');
    name = strrep(name, ':', '_colon_');
    name = strrep(name, '.', '_dot_');

    attr = parseAttributes(theNode);
    if (isempty(fieldnames(attr))) 
        attr = []; 
    end
    
    %parse child nodes
    [childs,text,textflag] = parseChildNodes(theNode);
    
    if (isempty(fieldnames(childs)) && isempty(fieldnames(text)))
        %get the data of any childless nodes
        % faster than if any(strcmp(methods(theNode), 'getData'))
        % no need to try-catch (?)
        % faster than text = char(getData(theNode));
        text.(textflag) = toCharArray(getTextContent(theNode))';
    end
    
end

% ----- Subfunction parseAttributes -----
function attributes = parseAttributes(theNode)
    % Create attributes structure.

    attributes = struct;
    if hasAttributes(theNode)
       theAttributes = getAttributes(theNode);
       numAttributes = getLength(theAttributes);

       for count = 1:numAttributes
            %attrib = item(theAttributes,count-1);
            %attr_name = regexprep(char(getName(attrib)),'[-:.]','_');
            %attributes.(attr_name) = char(getValue(attrib));

            %Suggestion of Adrian Wanner
            str = toCharArray(toString(item(theAttributes,count-1)))';
            k = strfind(str,'='); 
            attr_name = str(1:(k(1)-1));
            attr_name = strrep(attr_name, '-', '_dash_');
            attr_name = strrep(attr_name, ':', '_colon_');
            attr_name = strrep(attr_name, '.', '_dot_');
            attributes.(attr_name) = str((k(1)+2):(end-1));
       end
    end
end
