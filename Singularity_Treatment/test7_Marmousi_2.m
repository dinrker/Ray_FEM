%% Marmousi wave speed case

clear;
addpath(genpath('../../ifem/'));
addpath('../Methods/');
addpath('../Functions/')
addpath('../Plots_Prints/');


%% Set up
plt = 0;                   % show solution or not
fquadorder = 3;            % numerical quadrature order
Nray = 4;                  % one ray direction
sec_opt = 0;               % NMLA second order correction or not
pct = 0.25;

xs = 0; ys = 0.3;          % source location
epsilon = 1/(4*pi);        % cut-off parameter

% frequency
high_omega = 200*pi;
low_omega = 2*sqrt(high_omega);
wl = 2*pi/high_omega;

% width of PML
high_wpml = 0.1;
low_wpml = 0.25;

% mesh size
h = 1/400;  h_c = 1/100;

% load Marmousi data
load('Marmousi_smoother.mat');  
hr = 1/4000; mr = 8001; nr = 16001; xr = 2; yr = 1;

% compress Marmousi data
nh = round(h/hr);
ix = 1:nh:mr;  iy = 1:nh:nr;
Marmousi_compressed = Marmousi_smoother(ix,iy);
Marmousi_speed = Marmousi_compressed(:);
clear ix iy Marmousi_smoother Marmousi_compressed;

% construct Marmousi speed
speed = @(p) Marmousi_speed( Marmousi_index(p, xr, yr, h) )/1500;    % wave speed

% domains
sdx = 1.5; sdy = 0.5;
mdx = 1.65; mdy = 0.65;
ldx = 2; ldy = 1;

large_domain = [-ldx, ldx, -ldy, ldy];
middle_domain = [-mdx, mdx, -mdy, mdy];
middle_domain_up = [-mdx, mdx, 0.2, mdy];
middle_domain_down = [-mdx, mdx, -mdy, 0.2];

small_domain = [-sdx, sdx, -sdy, sdy];
small_domain_up = [-sdx, sdx, 0.2, sdy];
small_domain_down = [-sdx, sdx, -sdy, 0.2];


fprintf(['-'*ones(1,80) '\n']);
fprintf('Marmousi wave speed case: \n');
fprintf(['-'*ones(1,80) '\n']);
fprintf('Computational domain = \n  [%.2f, %.2f, %.2f, %.2f] \n', large_domain);
fprintf(['-'*ones(1,80) '\n']);
fprintf('  Wavelength = %.2d    NPW = %d    \n  1/h = %d    1/h_c = %d \n', wl, round(wl/h), round(1/h), round(1/h_c) );


tstart = tic;
%% Step 1: Solve the Hemholtz equation with the same source but with a relative low frequency sqrt(\omega) by Standard FEM, mesh size \omega*h = constant
fprintf(['-'*ones(1,80) '\n']);
fprintf('Step1: S-FEM, low frequency \n');
tic;
omega = low_omega;              % low frequency
wpml = low_wpml;                % width of PML
sigmaMax = 25/wpml;                 % Maximun absorbtion
[lnode,lelem] = squaremesh(large_domain,h);

% smooth part
A = assemble_Helmholtz_matrix_SFEM(lnode,lelem,omega,wpml,sigmaMax,speed,fquadorder);
b = assemble_RHS_SFEM_with_ST(lnode,lelem,xs,ys,omega,wpml,sigmaMax,epsilon,fquadorder);
[~,~,isBdNode] = findboundary(lelem);
freeNode = find(~isBdNode);
lN = size(lnode,1);        u_std = zeros(lN,1);
u_std(freeNode) = A(freeNode,freeNode)\b(freeNode);

% singular part
x = lnode(:,1); y = lnode(:,2);
rr = sqrt((x-xs).^2 + (y-ys).^2);
ub = 1i/4*besselh(0,1,omega*rr);
cf = cutoff(epsilon,2*epsilon,lnode,xs,ys);

% low frequency solution: smooth + singularity
u_low = u_std + ub.*cf;
toc;

% figure(71); showsolution(lnode,lelem,real(u_low),2); colorbar;axis equal; axis tight;

%% Step 2: Use NMLA to find ray directions d_c with low frequency sqrt(\omega)
fprintf(['-'*ones(1,80) '\n']);
fprintf('Step2: NMLA, low frequency \n');

% compute numerical derivatives
m = round( (large_domain(2) - large_domain(1)) /h ) + 1;
n = round( (large_domain(4) - large_domain(3)) /h ) + 1;
[ux,uy] = num_derivative(u_low,h,2,m,n);


% all middle domain: homogeneous + inhomogeneous
[mnode,melem] = squaremesh(middle_domain,h);
mN = size(mnode,1);  mNdof = 0;  mcompressed = 0;
mray = cell(mN,1);

tic;
for mi = 1:mN
    x0 = mnode(mi,1);  y0 = mnode(mi,2);
    r0 = sqrt((x0-xs)^2 + (y0-ys)^2);
    c0 = speed(mnode(mi,:));
    Rest = min(1.5, r0);
    if y0 >= middle_domain_up(3)  % upper part: homogeneous
        mray{mi} = ex_ray([x0,y0],xs,ys,1);
        mNdof = mNdof + 1;
    else  % lower part: inhomogeneous
        angles = NMLA(x0,y0,c0,omega,Rest,lnode,lelem,u_low,ux,uy,[],1/4,Nray,'num',sec_opt,plt);
        mray{mi} = exp(1i*angles);
        mNdof = mNdof + length(angles);  
    end
end
toc;

% % upper part: homogeneous
% [node_up,~] = squaremesh(middle_domain_up,h);
% ray_up = ex_ray(node_up,xs,ys,1);
% 
% m_up = round( (middle_domain_up(2) - middle_domain_up(1)) /h ) + 1;
% n_up = round( (middle_domain_up(4) - middle_domain_up(3)) /h ) + 1;
% 
% % lower part: inhomogeneous
% [cnode,celem] = squaremesh(middle_domain_down,h_c);
% cx = middle_domain_down(1):h_c:middle_domain_down(2);
% cy = middle_domain_down(3):h_c:middle_domain_down(4);
% cm = length(cx);  %round( (middle_domain_down(2) - middle_domain_down(1)) /h_c ) + 1;
% cn = length(cy);  %round( (middle_domain_down(4) - middle_domain_down(3)) /h_c ) + 1;
% cN = size(cnode,1);  cray_down = zeros(cN, Nray);
% angles_prev = [pi/4, 3*pi/4, 5*pi/4, 7*pi/4];
% 
% tic;
% for ci = 1:cN
%     x0 = cnode(ci,1);  y0 = cnode(ci,2);
%     r0 = sqrt((x0-xs)^2 + (y0-ys)^2);
%     c0 = speed(cnode(ci,:));
%     Rest = min(1, r0);
%     angles = NMLA(x0,y0,c0,omega,Rest,lnode,lelem,u_low,ux,uy,[],1/4,Nray,'num',sec_opt,plt);
%     if length(angles) == 4
%         angles_prev = angles;
%     else
%         idx = post_helper(angles);
%         if (ci>1) && (mode(ci, cn) == 1)
%             angles_prev = cray_down(ci-cn,:);
%         end
%         angles_prev(idx) = angles;
%     end
%     cray_down(ci,:) = angles_prev;
% end
% toc;
% 
% cray_down = exp(1i*cray_down);
% [node_down,~] = squaremesh(middle_domain_down,h);
% ray_down = interpolation(cnode, celem, node_down, cray_down);
% ray_down = ray_down./abs(ray_down);
% 
% m_down = round( (middle_domain_down(2) - middle_domain_down(1)) /h ) + 1;
% n_down = round( (middle_domain_down(4) - middle_domain_down(3)) /h ) + 1;
%     
% 
% % all middle domain: homogeneous + inhomogeneous
% [mnode,melem] = squaremesh(middle_domain,h);
% mN = size(mnode,1);  mNdof = 0;  mcompressed = 0;
% mray = cell(mN,1);
% 
% tic;
% for mi = 1:mN
%     mx = mnode(mi,1);  my = mnode(mi,2);
%     ix = round( (mx - middle_domain(1)) /h );
%     if my >= middle_domain_up(3)  % upper part: homogeneous
%         iy = round( (my - middle_domain_up(3)) /h );
%         idx = ix*n_up + iy + 1;
%         mray{mi} = ray_up(idx,:);
%         mNdof = mNdof + 1;
%     else  % lower part: inhomogeneous
%         iy = round( (my - middle_domain_down(3)) /h );
%         idx = ix*n_down + iy + 1;
%         rays_comp = post_compressor(ray_down(idx,:), pct);
%         mray{mi} = rays_comp;
%         ncomp = length(rays_comp);
%         mNdof = mNdof + ncomp;  
%         mcompressed = mcompressed + (4 - ncomp);
%     end
% end
% toc;

% figure(72); ray_field(mray,mnode,20,1/10);
        

%% Step 3: Solve the original Helmholtz equation by Ray-based FEM with ray directions d_c
fprintf(['-'*ones(1,80) '\n']);
fprintf('Step3: Ray-FEM, high frequency \n');

omega = high_omega;
wpml = high_wpml;                % width of PML
sigmaMax = 25/wpml;                 % Maximun absorbtion
ray = mray;

% smooth part
option ='homogeneous'; 
tic;
A = assemble_Helmholtz_matrix_RayFEM(mnode,melem,omega,wpml,sigmaMax,speed,ray,fquadorder);
toc;
tic;
b = assemble_RHS_RayFEM_with_ST(mnode,melem,xs,ys,omega,epsilon,wpml,sigmaMax,ray,speed,fquadorder,option);
toc;
tic;
uh = RayFEM_direct_solver(mnode,melem,A,b,omega,ray,speed);
toc;

% singularity part
x = mnode(:,1); y = mnode(:,2);
rr = sqrt((x-xs).^2 + (y-ys).^2);
ub = 1i/4*besselh(0,1,omega*rr);
cf = cutoff(epsilon,2*epsilon,mnode,xs,ys);

% smooth + singularity
uh1 = uh + ub.*cf;

% figure(73); showsolution(mnode,melem,real(uh1),2); colorbar; axis equal; axis tight;


%% Step 4: NMLA to find original ray directions d_o with wavenumber k
fprintf(['-'*ones(1,80) '\n']);
fprintf('Step4: NMLA, high frequency \n');
tic;

% compute numerical derivatives
m = round( (middle_domain(2) - middle_domain(1)) /h ) + 1;
n = round( (middle_domain(4) - middle_domain(3)) /h ) + 1;
[ux,uy] = num_derivative(uh1,h,2,m,n);


% all small domain: homogeneous + inhomogeneous
[node,elem] = squaremesh(small_domain,h);
N = size(node,1);  Ndof = 0;  compressed = 0;
ray = cell(N,1);

tic;
for i = 1:N
    x0 = node(i,1);  y0 = node(i,2);
    r0 = sqrt((x0-xs)^2 + (y0-ys)^2);
    c0 = speed(node(i,:));
    Rest = min(1.5, r0);
    if y0 >= small_domain_up(3)  % upper part: homogeneous
        ray{i} = ex_ray([x0,y0],xs,ys,1);
        Ndof = Ndof + 1;
    else  % lower part: inhomogeneous
        angles = NMLA(x0,y0,c0,omega,Rest,mnode,melem,uh1,ux,uy,[],1/4,Nray,'num',sec_opt,plt);
        ray{i} = exp(1i*angles);
        Ndof = Ndof + length(angles);  
    end
end
toc;







% 
% % upper part: homogeneous
% [node_up,~] = squaremesh(small_domain_up,h);
% ray_up = ex_ray(node_up,xs,ys,1);
% 
% m_up = round( (small_domain_up(2) - small_domain_up(1)) /h ) + 1;
% n_up = round( (small_domain_up(4) - small_domain_up(3)) /h ) + 1;
% 
% % lower part: inhomogeneous
% [cnode,celem] = squaremesh(small_domain_down,h_c);
% cx = small_domain_down(1):h_c:small_domain_down(2);
% cy = small_domain_down(3):h_c:small_domain_down(4);
% cm = length(cx);  %round( (small_domain_down(2) - small_domain_down(1)) /h_c ) + 1;
% cn = length(cy);  %round( (small_domain_down(4) - small_domain_down(3)) /h_c ) + 1;
% cN = size(cnode,1);  cray_down = zeros(cN, Nray);
% angles_prev = [pi/4, 3*pi/4, 5*pi/4, 7*pi/4];
% 
% tic;
% for ci = 1:cN
%     x0 = cnode(ci,1);  y0 = cnode(ci,2);
%     r0 = sqrt((x0-xs)^2 + (y0-ys)^2);
%     c0 = speed(cnode(ci,:));
%     Rest = min(1, r0);
%     angles = NMLA(x0,y0,c0,omega,Rest,mnode,melem,uh1,ux,uy,[],1/4,Nray,'num',sec_opt,plt);
%     if length(angles) == 4
%         angles_prev = angles;
%     else
%         idx = post_helper(angles);
%         if (ci>1) && (mode(ci, cn) == 1)
%             angles_prev = cray_down(ci-cn,:);
%         end
%         angles_prev(idx) = angles;
%     end
%     cray_down(ci,:) = angles_prev;
% end
% toc;
% 
% cray_down = exp(1i*cray_down);
% [node_down,~] = squaremesh(small_domain_down,h);
% ray_down = interpolation(cnode, celem, node_down, cray_down);
% ray_down = ray_down./abs(ray_down);
% 
% m_down = round( (small_domain_down(2) - small_domain_down(1)) /h ) + 1;
% n_down = round( (small_domain_down(4) - small_domain_down(3)) /h ) + 1;
%     
% 
% % all small domain: homogeneous + inhomogeneous
% [node,elem] = squaremesh(small_domain,h);
% N = size(node,1);  Ndof = 0;  compressed = 0;
% ray = cell(N,1);
% 
% tic;
% for i = 1:N
%     x = node(i,1);  y = node(i,2);
%     ix = round( (x - small_domain(1)) /h );
%     if y >= small_domain_up(3)  % upper part: homogeneous
%         iy = round( (y - small_domain_up(3)) /h );
%         idx = ix*n_up + iy + 1;
%         ray{i} = ray_up(idx,:);
%         Ndof = Ndof + 1;
%     else
%         iy = round( (y - small_domain_down(3)) /h );
%         idx = ix*n_down + iy + 1;
%         rays_comp = post_compressor(ray_down(idx,:), pct);
%         ray{i} = rays_comp;
%         ncomp = length(rays_comp);
%         Ndof = Ndof + ncomp;  
%         compressed = compressed + (4 - ncomp);
%     end
% end
% toc;

% figure(74); ray_field(ray,node,20,1/10); axis equal; axis tight;


%% Step 5: Solve the original Helmholtz equation by Ray-based FEM with ray directions d_o
fprintf([ '-'*ones(1,80) '\n']);
fprintf('Step5: Ray-FEM, high frequency \n');

omega = high_omega;
wpml = 0.1;                % width of PML
sigmaMax = 25/wpml;                 % Maximun absorbtion

% Assembling
tic;
A = assemble_Helmholtz_matrix_RayFEM(node,elem,omega,wpml,sigmaMax,speed,ray,fquadorder);
toc; 
tic;
b = assemble_RHS_RayFEM_with_ST(node,elem,xs,ys,omega,epsilon,wpml,sigmaMax,ray,speed,fquadorder,option);
toc;
tic;
uh = RayFEM_direct_solver(node,elem,A,b,omega,ray,speed);
toc;

% singularity part
x = node(:,1); y = node(:,2);
rr = sqrt((x-xs).^2 + (y-ys).^2);
ub = 1i/4*besselh(0,1,omega*rr);
cf = cutoff(epsilon,2*epsilon,node,xs,ys);

% smooth + singularity
uh2 = uh + ub.*cf;

% figure(75); showsolution(node,elem,real(uh2),2); colorbar; axis equal; axis tight;


totaltime = toc(tstart);
fprintf('\n\nTotal running time: % d minutes \n', totaltime/60);

nameFile = strcat('resutls_7_Marmousi.mat');
save(nameFile, 'uh2', 'h', 'high_omega');

figure(70);
m = round( (small_domain(2) - small_domain(1)) /h ) + 1;
n = round( (small_domain(4) - small_domain(3)) /h ) + 1;
uh22 = reshape(real(uh2), n, m);
imagesc(uh22(end:-1:1, :)); axis equal; axis tight; colorbar;


